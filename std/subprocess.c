#include "../runtime/platform.h"
#include "subprocess.h"
#include "../runtime/api.h"

/* Child processes for std.subprocess. A child starts with posix_spawnp; each
 * piped standard stream is one end of a socketpair, so the parent's end is an
 * ordinary AsyncStream. A detached thread waits for the child as soon as it
 * starts, so no zombie remains even if the program never waits, then writes a
 * byte into a pipe that wait operations poll; the byte stays unread, so every
 * later wait completes at once. The job is shared by the thread and the Child
 * object and freed by whichever finishes with it last. */

#if defined(__unix__) || defined(__APPLE__)
#include <pthread.h>
#include <spawn.h>
#include <signal.h>
#if defined(__APPLE__)
#include <crt_externs.h>
#define CHILD_ENVIRON (*_NSGetEnviron())
#else
extern char** environ;
#define CHILD_ENVIRON environ
#endif

typedef struct ChildJob {
    pthread_mutex_t lock;
    int owners;     /* the waiting thread and the Child object */
    pid_t pid;
    int done;       /* the child has been reaped */
    int status;     /* waitpid status */
    int notify;     /* pipe write end, owned by the thread */
    int ready;      /* pipe read end, readable once the child is reaped */
} ChildJob;

static void child_job_release(ChildJob* job) {
    pthread_mutex_lock(&job->lock);
    int left = --job->owners;
    pthread_mutex_unlock(&job->lock);
    if (left) return;
    pthread_mutex_destroy(&job->lock);
    close(job->ready);
    free(job);
}

static void* child_wait_thread(void* argument) {
    ChildJob* job = argument;
    int status = 0;
    pid_t waited;
    do { waited = waitpid(job->pid, &status, 0); } while (waited < 0 && errno == EINTR);
    pthread_mutex_lock(&job->lock);
    job->status = waited < 0 ? 0 : status;
    job->done = 1;
    pthread_mutex_unlock(&job->lock);
    char byte = 1;
    ssize_t written = write(job->notify, &byte, 1);
    (void)written;
    close(job->notify);
    child_job_release(job);
    return NULL;
}

/* NUL-terminated copies of a Vec<String>'s elements, or NULL when one holds NUL. */
static char** child_strings(void* vec, int* count) {
    GVecHeader* header = vec;
    int n = header ? header->len : 0;
    char** out = calloc((size_t)n + 1, sizeof(char*));
    if (!out) rt_panic("subprocess allocation failed");
    unsigned char* data = header ? (unsigned char*)(header + 1) : NULL;
    for (int i = 0; i < n; i++) {
        StringVal value = rt_string_obj_value(*(void**)(data + (size_t)i * (size_t)header->elem_size));
        if (value.len < 0 || (value.len && memchr(value.data, 0, (size_t)value.len))) {
            for (int j = 0; j < i; j++) free(out[j]);
            free(out); return NULL;
        }
        out[i] = malloc((size_t)value.len + 1);
        if (!out[i]) rt_panic("subprocess allocation failed");
        if (value.len) memcpy(out[i], value.data, (size_t)value.len);
        out[i][value.len] = 0;
    }
    *count = n;
    return out;
}

static void child_free_strings(char** strings, int count) {
    if (!strings) return;
    for (int i = 0; i < count; i++) free(strings[i]);
    free(strings);
}

/* The environment: the parent's unless cleared, with `overrides` ("NAME=value") replacing or adding. */
static char** child_environment(char** overrides, int override_count, int cleared, int* count) {
    int inherited = 0;
    if (!cleared) for (char** item = CHILD_ENVIRON; item && *item; item++) inherited++;
    char** out = calloc((size_t)(inherited + override_count) + 1, sizeof(char*));
    if (!out) rt_panic("subprocess allocation failed");
    int n = 0;
    if (!cleared) for (char** item = CHILD_ENVIRON; item && *item; item++) {
        const char* equals = strchr(*item, '=');
        size_t name = equals ? (size_t)(equals - *item) : strlen(*item);
        int replaced = 0;
        for (int i = 0; i < override_count && !replaced; i++)
            if (strncmp(overrides[i], *item, name) == 0 && overrides[i][name] == '=') replaced = 1;
        if (!replaced) out[n++] = *item;
    }
    for (int i = 0; i < override_count; i++) out[n++] = overrides[i];
    *count = n;
    return out;
}

static int child_socketpair(int fds[2]) {
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) < 0) return errno;
    (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC); (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    return 0;
}

/* Starts `program` (searched in PATH) with `arguments` (argv[0] first). Modes
 * are 0 inherit, 1 pipe, 2 /dev/null. Piped streams are returned through
 * `input`, `output` and `errors`. Returns the child, or NULL with `error` set. */
void* rt_child_spawn(void* program_string, void* arguments, void* environment, int32_t cleared,
                     void* directory, int32_t in_mode, int32_t out_mode, int32_t err_mode,
                     void** input, void** output, void** errors, int32_t* error) {
    *error = 0;
    void** streams[3] = { input, output, errors };
    *input = *output = *errors = NULL;
    StringVal program_value = rt_string_obj_value(program_string);
    if (program_value.len <= 0 || memchr(program_value.data, 0, (size_t)program_value.len)) { *error = EINVAL; return NULL; }
    char* program = malloc((size_t)program_value.len + 1);
    if (!program) rt_panic("subprocess allocation failed");
    memcpy(program, program_value.data, (size_t)program_value.len); program[program_value.len] = 0;
    StringVal directory_value = rt_string_obj_value(directory);
    char* cwd = NULL;
    if (directory_value.len > 0) {
        if (memchr(directory_value.data, 0, (size_t)directory_value.len)) { free(program); *error = EINVAL; return NULL; }
        cwd = malloc((size_t)directory_value.len + 1);
        if (!cwd) rt_panic("subprocess allocation failed");
        memcpy(cwd, directory_value.data, (size_t)directory_value.len); cwd[directory_value.len] = 0;
    }
    int argc = 0, override_count = 0, envc = 0;
    char** argv = child_strings(arguments, &argc);
    char** overrides = child_strings(environment, &override_count);
    if (!argv || !overrides) {
        child_free_strings(argv, argc); child_free_strings(overrides, override_count);
        free(program); free(cwd); *error = EINVAL; return NULL;
    }
    char** envp = child_environment(overrides, override_count, cleared, &envc);
    int modes[3] = { in_mode, out_mode, err_mode };
    int pairs[3][2] = { { -1, -1 }, { -1, -1 }, { -1, -1 } };
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    /* The child starts with default signal handling (the parent may ignore SIGPIPE). */
    sigset_t defaults; sigemptyset(&defaults); sigaddset(&defaults, SIGPIPE);
    posix_spawnattr_setsigdefault(&attributes, &defaults);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGDEF);
    int status = 0;
    for (int stream = 0; stream < 3 && !status; stream++) {
        if (modes[stream] == 1) {
            status = child_socketpair(pairs[stream]);
            if (!status) {
                posix_spawn_file_actions_adddup2(&actions, pairs[stream][1], stream);
            }
        } else if (modes[stream] == 2) {
            posix_spawn_file_actions_addopen(&actions, stream, "/dev/null", stream == 0 ? O_RDONLY : O_WRONLY, 0);
        }
    }
    if (!status && cwd) {
#if defined(__APPLE__) || (defined(__GLIBC__) && (__GLIBC__ > 2 || __GLIBC_MINOR__ >= 29))
        status = posix_spawn_file_actions_addchdir_np(&actions, cwd);
#else
        status = ENOSYS;
#endif
    }
    pid_t pid = 0;
    if (!status) status = posix_spawnp(&pid, program, &actions, &attributes, argv, envp);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    free(envp);
    child_free_strings(argv, argc); child_free_strings(overrides, override_count);
    free(program); free(cwd);
    for (int stream = 0; stream < 3; stream++) if (pairs[stream][1] >= 0) close(pairs[stream][1]);
    if (status) {
        for (int stream = 0; stream < 3; stream++) if (pairs[stream][0] >= 0) close(pairs[stream][0]);
        *error = status; return NULL;
    }
    for (int stream = 0; stream < 3; stream++) if (pairs[stream][0] >= 0) {
        *streams[stream] = rl_stream_adopt(pairs[stream][0]);
        if (!*streams[stream]) rt_panic("subprocess stream setup failed");
    }
    ChildJob* job = calloc(1, sizeof(*job));
    if (!job) rt_panic("subprocess allocation failed");
    pthread_mutex_init(&job->lock, NULL);
    job->pid = pid; job->owners = 2;
    int fds[2];
    if (pipe(fds) < 0) rt_panic("subprocess pipe failed");
    (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC); (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    job->ready = fds[0]; job->notify = fds[1];
    pthread_t thread;
    if (pthread_create(&thread, NULL, child_wait_thread, job) != 0) rt_panic("cannot start the subprocess wait thread");
    pthread_detach(thread);
    return job;
}

int32_t rt_child_pid(void* child) { return (int32_t)((ChildJob*)child)->pid; }

void rt_child_release(void* child) { if (child) child_job_release(child); }

/* Completes once the child has exited. */
TaskHandle* rt_child_wait_start(void* child) {
    ChildJob* job = child;
    TaskHandle* task = rl_task_new(); task->native_kind = 11;
    int fd = dup(job->ready);
    if (fd < 0) { rl_task_native_result(task, -errno); return task; }
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    AsyncStream* stream = malloc(sizeof(*stream));
    if (!stream) rt_panic("subprocess allocation failed");
    stream->fd = fd; stream->refs = 1; task->stream = stream;
    return task;
}

/* The exit code, or -1 with `signal` set when a signal ended the child. */
int32_t rt_child_status(void* child, int32_t* signal) {
    ChildJob* job = child;
    pthread_mutex_lock(&job->lock);
    int status = job->status;
    pthread_mutex_unlock(&job->lock);
    *signal = 0;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) { *signal = WTERMSIG(status); return -1; }
    return -1;
}

/* Sends `signal` unless the child was already reaped (its pid may be reused). */
int32_t rt_child_kill(void* child, int32_t signal) {
    ChildJob* job = child;
    pthread_mutex_lock(&job->lock);
    int result = job->done ? -ESRCH : (kill(job->pid, signal) == 0 ? 0 : -errno);
    pthread_mutex_unlock(&job->lock);
    return result;
}

#else

void* rt_child_spawn(void* program, void* arguments, void* environment, int32_t cleared,
                     void* directory, int32_t in_mode, int32_t out_mode, int32_t err_mode,
                     void** input, void** output, void** errors, int32_t* error) {
    (void)program; (void)arguments; (void)environment; (void)cleared; (void)directory;
    (void)in_mode; (void)out_mode; (void)err_mode;
    *input = *output = *errors = NULL; *error = ENOSYS; return NULL;
}
int32_t rt_child_pid(void* child) { (void)child; return -1; }
void rt_child_release(void* child) { (void)child; }
TaskHandle* rt_child_wait_start(void* child) {
    (void)child; TaskHandle* task = rl_task_new(); task->native_kind = 11;
    rl_task_native_result(task, -ENOSYS); return task;
}
int32_t rt_child_status(void* child, int32_t* signal) { (void)child; *signal = 0; return -1; }
int32_t rt_child_kill(void* child, int32_t signal) { (void)child; (void)signal; return -ENOSYS; }

#endif
