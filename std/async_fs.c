#include "../runtime/platform.h"
#include "async_fs.h"
#include "random.h"
#include "../runtime/api.h"

/* Asynchronous file operations for std.async_fs. Regular files are always
 * "ready" to poll, so each operation runs on a small pool of worker threads
 * (at most four, started on demand) and signals completion through a pipe the
 * scheduler polls, like name resolution. A job is shared by its task and its
 * worker and freed by whichever finishes with it last, so cancelling a task
 * never frees memory a worker still uses. Workers touch no Rolang objects. */

#if defined(__unix__) || defined(__APPLE__)
#include <pthread.h>
#include <dirent.h>

enum { FS_READ = 1, FS_WRITE, FS_WRITE_ATOMIC, FS_LIST, FS_STAT, FS_REMOVE, FS_MKDIR, FS_RENAME };
#define FS_WORKERS 4

typedef struct FsJob {
    pthread_mutex_t lock;
    int owners;
    int op;
    char* path;
    char* other;            /* rename target */
    char* input; size_t input_size;
    int64_t limit, flags;
    int error;              /* errno, 0 on success */
    char* output; size_t output_size;
    int64_t values[6];      /* stat: size, mode, mtime seconds, mtime nanoseconds, kind, written */
    int notify;
    struct FsJob* next;
} FsJob;

static pthread_mutex_t fs_queue_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t fs_queue_ready = PTHREAD_COND_INITIALIZER;
static FsJob* fs_queue_head;
static FsJob* fs_queue_tail;
static int fs_workers, fs_idle;

static void fs_job_release(FsJob* job) {
    pthread_mutex_lock(&job->lock);
    int left = --job->owners;
    pthread_mutex_unlock(&job->lock);
    if (left) return;
    pthread_mutex_destroy(&job->lock);
    free(job->path); free(job->other); free(job->input); free(job->output);
    free(job);
}

static FsJob* fs_job_of(TaskHandle* task) { FsJob* job; memcpy(&job, task->peer, sizeof(job)); return job; }

/* Opens without blocking (a FIFO with no writer would hold a worker
 * forever), then refuses FIFOs and sockets: only files and devices, whose
 * reads and writes finish, are handled. */
static int fs_open(const char* path, int flags, int* fd_out) {
    int fd = open(path, flags | O_NONBLOCK | O_CLOEXEC, 0644);
    if (fd < 0) return errno == ENXIO ? EINVAL : errno;
    struct stat info;
    if (fstat(fd, &info) != 0) { int error = errno; close(fd); return error; }
    if (S_ISFIFO(info.st_mode) || S_ISSOCK(info.st_mode)) { close(fd); return EINVAL; }
    if (S_ISDIR(info.st_mode)) { close(fd); return EISDIR; }
    int current = fcntl(fd, F_GETFL);
    if (current >= 0) (void)fcntl(fd, F_SETFL, current & ~O_NONBLOCK);
    *fd_out = fd;
    return 0;
}

static int fs_read_file(FsJob* job) {
    int fd = -1;
    int opened = fs_open(job->path, O_RDONLY, &fd);
    if (opened) return opened;
    struct stat info;
    if (fstat(fd, &info) != 0) { int error = errno; close(fd); return error; }
    size_t capacity = info.st_size > 0 && info.st_size < job->limit ? (size_t)info.st_size + 1 : 65536;
    char* data = malloc(capacity + 1);
    if (!data) { close(fd); return ENOMEM; }
    size_t used = 0;
    while (1) {
        if (used == capacity) {
            if ((int64_t)capacity > job->limit) { free(data); close(fd); return EFBIG; }
            size_t next = capacity * 2;
            char* grown = realloc(data, next + 1);
            if (!grown) { free(data); close(fd); return ENOMEM; }
            data = grown; capacity = next;
        }
        ssize_t got = read(fd, data + used, capacity - used);
        if (got < 0) { if (errno == EINTR) continue; int error = errno; free(data); close(fd); return error; }
        if (got == 0) break;
        used += (size_t)got;
        if ((int64_t)used > job->limit) { free(data); close(fd); return EFBIG; }
    }
    close(fd);
    data[used] = 0;
    job->output = data; job->output_size = used;
    return 0;
}

static int fs_write_all(int fd, const char* data, size_t size) {
    size_t done = 0;
    while (done < size) {
        ssize_t wrote = write(fd, data + done, size - done);
        if (wrote < 0) { if (errno == EINTR) continue; return errno; }
        done += (size_t)wrote;
    }
    return 0;
}

/* flags: 0 replace, 1 append, 2 create only (fails if the file exists). */
static int fs_write_file(FsJob* job) {
    int mode = O_WRONLY | O_CREAT;
    if (job->flags == 1) mode |= O_APPEND; else if (job->flags == 2) mode |= O_EXCL;
    int fd = -1;
    int opened = fs_open(job->path, mode, &fd);
    if (opened) return opened;
    /* Truncate only once the target is known to be a file or device. */
    if (job->flags == 0 && ftruncate(fd, 0) != 0 && errno != EINVAL) { int error = errno; close(fd); return error; }
    int error = fs_write_all(fd, job->input, job->input_size);
    if (close(fd) != 0 && !error) error = errno;
    job->values[5] = (int64_t)job->input_size;
    return error;
}

/* Writes a temporary file beside the target, flushes it and renames it over
 * the target, so readers see the old or the new contents, never a mixture. */
static int fs_write_atomic(FsJob* job) {
    size_t length = strlen(job->path);
    char* temporary = malloc(length + 32);
    if (!temporary) return ENOMEM;
    /* The temporary file is created like a new file (0666 less the umask);
     * replacing an existing file keeps that file's permissions. */
    int fd = -1;
    for (int attempt = 0; attempt < 16 && fd < 0; attempt++) {
        uint64_t suffix = rt_random_entropy();
        snprintf(temporary, length + 32, "%s.tmp.%016llx", job->path, (unsigned long long)suffix);
        fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0666);
        if (fd < 0 && errno != EEXIST) break;
    }
    if (fd < 0) { int error = errno; free(temporary); return error; }
    struct stat existing;
    if (stat(job->path, &existing) == 0) {
        if (!S_ISREG(existing.st_mode)) { close(fd); unlink(temporary); free(temporary); return EINVAL; }
        (void)fchmod(fd, existing.st_mode & 07777);
    }
    int error = fs_write_all(fd, job->input, job->input_size);
    if (!error && fsync(fd) != 0) error = errno;
    if (close(fd) != 0 && !error) error = errno;
    if (!error && rename(temporary, job->path) != 0) error = errno;
    if (error) unlink(temporary);
    free(temporary);
    job->values[5] = (int64_t)job->input_size;
    return error;
}

/* Names separated by NUL bytes (which names cannot contain). */
static int fs_list(FsJob* job) {
    DIR* directory = opendir(job->path);
    if (!directory) return errno;
    size_t capacity = 1024, used = 0;
    char* out = malloc(capacity);
    if (!out) { closedir(directory); return ENOMEM; }
    struct dirent* entry;
    errno = 0;
    while ((entry = readdir(directory))) {
        const char* name = entry->d_name;
        if (!strcmp(name, ".") || !strcmp(name, "..")) continue;
        size_t size = strlen(name);
        while (used + size + 2 > capacity) {
            capacity *= 2;
            char* grown = realloc(out, capacity);
            if (!grown) { free(out); closedir(directory); return ENOMEM; }
            out = grown;
        }
        if (used) out[used++] = 0;
        memcpy(out + used, name, size); used += size;
    }
    int error = errno;
    closedir(directory);
    if (error) { free(out); return error; }
    out[used] = 0;
    job->output = out; job->output_size = used;
    return 0;
}

static int fs_stat(FsJob* job) {
    struct stat info;
    if (stat(job->path, &info) != 0) return errno;
    job->values[0] = (int64_t)info.st_size;
    job->values[1] = (int64_t)(info.st_mode & 07777);
#if defined(__APPLE__)
    job->values[2] = (int64_t)info.st_mtimespec.tv_sec; job->values[3] = (int64_t)info.st_mtimespec.tv_nsec;
#else
    job->values[2] = (int64_t)info.st_mtim.tv_sec; job->values[3] = (int64_t)info.st_mtim.tv_nsec;
#endif
    job->values[4] = S_ISDIR(info.st_mode) ? 1 : S_ISREG(info.st_mode) ? 2 : S_ISLNK(info.st_mode) ? 3 : 0;
    return 0;
}

static int fs_mkdir(FsJob* job) {
    if (!job->flags) return mkdir(job->path, 0755) == 0 ? 0 : errno;
    /* Each missing parent in turn; existing directories are fine. */
    char* path = job->path;
    for (char* at = path + 1; ; at++) {
        if (*at == '/' || *at == 0) {
            char saved = *at; *at = 0;
            int failed = mkdir(path, 0755) != 0 && errno != EEXIST;
            int error = errno;
            *at = saved;
            if (failed) return error;
            if (!saved) break;
        }
    }
    struct stat info;
    if (stat(path, &info) != 0) return errno;
    return S_ISDIR(info.st_mode) ? 0 : ENOTDIR;
}

static void fs_run(FsJob* job) {
    switch (job->op) {
        case FS_READ: job->error = fs_read_file(job); break;
        case FS_WRITE: job->error = fs_write_file(job); break;
        case FS_WRITE_ATOMIC: job->error = fs_write_atomic(job); break;
        case FS_LIST: job->error = fs_list(job); break;
        case FS_STAT: job->error = fs_stat(job); break;
        case FS_REMOVE: {
            struct stat info;
            if (lstat(job->path, &info) != 0) job->error = errno;
            else job->error = (S_ISDIR(info.st_mode) ? rmdir(job->path) : unlink(job->path)) == 0 ? 0 : errno;
            break;
        }
        case FS_MKDIR: job->error = fs_mkdir(job); break;
        case FS_RENAME: job->error = rename(job->path, job->other) == 0 ? 0 : errno; break;
        default: job->error = EINVAL;
    }
}

static void* fs_worker(void* argument) {
    (void)argument;
    while (1) {
        pthread_mutex_lock(&fs_queue_lock);
        fs_idle++;
        while (!fs_queue_head) pthread_cond_wait(&fs_queue_ready, &fs_queue_lock);
        fs_idle--;
        FsJob* job = fs_queue_head;
        fs_queue_head = job->next;
        if (!fs_queue_head) fs_queue_tail = NULL;
        pthread_mutex_unlock(&fs_queue_lock);
        fs_run(job);
        char byte = 1;
        ssize_t written = write(job->notify, &byte, 1);
        (void)written;
        close(job->notify);
        fs_job_release(job);
    }
    return NULL;
}

static char* fs_copy_string(void* string, int* invalid) {
    StringVal value = rt_string_obj_value(string);
    if (value.len < 0 || (value.len && memchr(value.data, 0, (size_t)value.len))) { *invalid = 1; return NULL; }
    char* copy = malloc((size_t)value.len + 1);
    if (!copy) rt_panic("async fs allocation failed");
    if (value.len) memcpy(copy, value.data, (size_t)value.len);
    copy[value.len] = 0;
    return copy;
}

/* Queues an operation. `path` and `other` must not contain NUL; `input` may. */
TaskHandle* rt_fs_start(int32_t op, void* path, void* other, void* input, int64_t limit, int64_t flags) {
    TaskHandle* task = rl_task_new(); task->native_kind = 12;
    FsJob* job = calloc(1, sizeof(*job));
    if (!job) rt_panic("async fs allocation failed");
    pthread_mutex_init(&job->lock, NULL);
    job->owners = 1; job->op = op; job->limit = limit; job->flags = flags;
    memcpy(task->peer, &job, sizeof(job));
    int invalid = 0;
    job->path = fs_copy_string(path, &invalid);
    if (op == FS_RENAME) job->other = fs_copy_string(other, &invalid);
    if (invalid || !job->path || !job->path[0]) { job->error = EINVAL; rl_task_native_result(task, -1); return task; }
    if (op == FS_WRITE || op == FS_WRITE_ATOMIC) {
        StringVal value = rt_string_obj_value(input);
        job->input = malloc((size_t)value.len + 1);
        if (!job->input) rt_panic("async fs allocation failed");
        if (value.len) memcpy(job->input, value.data, (size_t)value.len);
        job->input_size = (size_t)value.len;
    }
    int fds[2];
    if (pipe(fds) < 0) { job->error = errno; rl_task_native_result(task, -1); return task; }
    (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC); (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    AsyncStream* stream = malloc(sizeof(*stream));
    if (!stream) rt_panic("async fs allocation failed");
    stream->fd = fds[0]; stream->refs = 1; task->stream = stream;
    job->notify = fds[1];
    job->owners = 2;
    pthread_mutex_lock(&fs_queue_lock);
    if (fs_queue_tail) fs_queue_tail->next = job; else fs_queue_head = job;
    fs_queue_tail = job;
    if (fs_idle == 0 && fs_workers < FS_WORKERS) {
        pthread_t thread;
        if (pthread_create(&thread, NULL, fs_worker, NULL) == 0) { pthread_detach(thread); fs_workers++; }
    }
    pthread_cond_signal(&fs_queue_ready);
    if (fs_workers == 0) rt_panic("cannot start an async fs worker thread");
    pthread_mutex_unlock(&fs_queue_lock);
    return task;
}

void rl_fs_ready(TaskHandle* task) {
    char byte;
    ssize_t got = read(task->stream->fd, &byte, 1);
    (void)got;
    rl_task_native_result(task, fs_job_of(task)->error ? -1 : 0);
}

void rl_fs_release(TaskHandle* task) { fs_job_release(fs_job_of(task)); }

/* After completion: the errno (0 on success), the output bytes and the values. */
int32_t rt_fs_error(TaskHandle* task) { rt_task_borrow_result(task); return fs_job_of(task)->error; }
void* rt_fs_output(TaskHandle* task) {
    rt_task_borrow_result(task);
    FsJob* job = fs_job_of(task);
    char* copy = malloc(job->output_size + 1);
    if (!copy) rt_panic("async fs allocation failed");
    if (job->output_size) memcpy(copy, job->output, job->output_size);
    copy[job->output_size] = 0;
    return rl_string_handle_from_value((StringVal){copy, (int64_t)job->output_size});
}
int64_t rt_fs_value(TaskHandle* task, int32_t index) {
    rt_task_borrow_result(task);
    return index >= 0 && index < 6 ? fs_job_of(task)->values[index] : 0;
}

#else

TaskHandle* rt_fs_start(int32_t op, void* path, void* other, void* input, int64_t limit, int64_t flags) {
    (void)op; (void)path; (void)other; (void)input; (void)limit; (void)flags;
    TaskHandle* task = rl_task_new(); task->native_kind = 12;
    rl_task_native_result(task, -1); return task;
}
void rl_fs_ready(TaskHandle* task) { (void)task; }
void rl_fs_release(TaskHandle* task) { (void)task; }
int32_t rt_fs_error(TaskHandle* task) { (void)task; return ENOSYS; }
void* rt_fs_output(TaskHandle* task) { (void)task; return rl_string_handle_from_value((StringVal){NULL, 0}); }
int64_t rt_fs_value(TaskHandle* task, int32_t index) { (void)task; (void)index; return 0; }

#endif
