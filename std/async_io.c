#include "../runtime/platform.h"
#include "async_io.h"
#include "../runtime/api.h"

/* Streams own nonblocking socket descriptors. Every pending operation retains
 * the stream, so closing the source wrapper cannot race descriptor reuse. */

/* Numeric addresses avoid blocking name resolution on the scheduler thread. */
#if defined(__unix__) || defined(__APPLE__)
static int tcp_address(void* string, int32_t port, struct sockaddr_storage* out,
                       socklen_t* size) {
    StringVal value = rt_string_obj_value(string);
    if (port < 0 || port > 65535 || value.len <= 0 || value.len >= INET6_ADDRSTRLEN)
        return EINVAL;
    char text[INET6_ADDRSTRLEN];
    if (memchr(value.data, 0, (size_t)value.len)) return EINVAL;
    memcpy(text, value.data, (size_t)value.len); text[value.len] = 0;
    memset(out, 0, sizeof(*out));
    struct sockaddr_in* v4 = (struct sockaddr_in*)out;
    if (inet_pton(AF_INET, text, &v4->sin_addr) == 1) {
        v4->sin_family = AF_INET; v4->sin_port = htons((uint16_t)port);
        *size = sizeof(*v4); return 0;
    }
    struct sockaddr_in6* v6 = (struct sockaddr_in6*)out;
    if (inet_pton(AF_INET6, text, &v6->sin6_addr) == 1) {
        v6->sin6_family = AF_INET6; v6->sin6_port = htons((uint16_t)port);
        *size = sizeof(*v6); return 0;
    }
    return EINVAL;
}
#endif

void rl_stream_release(AsyncStream* stream) {
    if (stream && --stream->refs == 0) {
#if defined(__unix__) || defined(__APPLE__)
        close(stream->fd);
#endif
        free(stream);
    }
}

static void rl_resolve_ready(TaskHandle* task);

void rl_async_ready(TaskHandle* task) {
#if defined(__unix__) || defined(__APPLE__)
    if (task->native_kind == 8) { rl_resolve_ready(task); return; }
    if (task->native_kind == 12) { rl_fs_ready(task); return; }
    if (task->native_kind == 13 || task->native_kind == 14) { rl_parallel_ready(task); return; }
    /* Readiness waits (TLS) leave the I/O to the waiting task. */
    if (task->native_kind == 9 || task->native_kind == 10 || task->native_kind == 11) { rl_task_native_result(task, 0); return; }
    if (task->native_kind == 4) {
        int error = 0;
        socklen_t size = sizeof(error);
        if (getsockopt(task->stream->fd, SOL_SOCKET, SO_ERROR, &error, &size) < 0)
            error = errno;
        if (!error) {
            task->result_stream = task->stream;
            task->result_stream->refs++;
        }
        rl_task_native_result(task, -error);
        return;
    }
    if (task->native_kind == 5) {
        int fd = accept(task->stream->fd, NULL, NULL);
        if (fd >= 0) {
            task->result_stream = rl_stream_adopt(fd);
            rl_task_native_result(task, task->result_stream ? 0 : -errno);
        } else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
            rl_task_native_result(task, -errno);
        return;
    }
    if (task->native_kind == 6) {
        ssize_t sent = sendto(task->stream->fd, task->buffer, (size_t)task->length, 0,
                              (struct sockaddr*)task->peer, (socklen_t)task->peer_size);
        if (sent >= 0) rl_task_native_result(task, (int32_t)sent);
        else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) rl_task_native_result(task, -errno);
        return;
    }
    if (task->native_kind == 7) {
        socklen_t size = sizeof(task->peer);
        ssize_t got = recvfrom(task->stream->fd, task->buffer, (size_t)task->length, 0,
                               (struct sockaddr*)task->peer, &size);
        if (got >= 0) { task->peer_size = (int32_t)size; task->offset = (int32_t)got; rl_task_native_result(task, (int32_t)got); }
        else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) rl_task_native_result(task, -errno);
        return;
    }
    ssize_t n;
    if (task->native_kind == 2) {
        n = recv(task->stream->fd, task->buffer, (size_t)task->length, 0);
        if (n >= 0) { task->offset = (int32_t)n; rl_task_native_result(task, (int32_t)n); }
    } else {
        int flags = 0;
#ifdef MSG_NOSIGNAL
        flags = MSG_NOSIGNAL;
#endif
        n = send(task->stream->fd, task->buffer + task->offset,
                 (size_t)(task->length - task->offset), flags);
        if (n > 0) {
            task->offset += (int32_t)n;
            if (task->offset == task->length) rl_task_native_result(task, task->offset);
        } else if (n == 0) rl_task_native_result(task, -EPIPE);
    }
    if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
        rl_task_native_result(task, -errno);
#else
    rl_task_native_result(task, -ENOSYS);
#endif
}

AsyncStream* rl_stream_adopt(int fd) {
#if defined(__unix__) || defined(__APPLE__)
    int socket_type;
    socklen_t type_len = sizeof(socket_type);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &socket_type, &type_len) < 0) {
        int error = errno; close(fd); errno = error; return NULL;
    }
    if (socket_type != SOCK_STREAM) { close(fd); errno = EINVAL; return NULL; }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        int error = errno; close(fd); errno = error; return NULL;
    }
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    int one = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) < 0) {
        int error = errno; close(fd); errno = error; return NULL;
    }
#endif
    AsyncStream* stream = malloc(sizeof(*stream));
    if (!stream) { close(fd); rt_panic("async stream allocation failed"); }
    stream->fd = fd; stream->refs = 1; return stream;
#else
    (void)fd; return NULL;
#endif
}

TaskHandle* rt_async_connect_start(void* address, int32_t port) {
    TaskHandle* task = rl_task_new(); task->native_kind = 4;
#if defined(__unix__) || defined(__APPLE__)
    struct sockaddr_storage addr; socklen_t size;
    int error = tcp_address(address, port, &addr, &size);
    if (error) { rl_task_native_result(task, -error); return task; }
    int fd = socket(addr.ss_family, SOCK_STREAM, 0);
    if (fd < 0) { rl_task_native_result(task, -errno); return task; }
    task->stream = rl_stream_adopt(fd);
    if (!task->stream) { rl_task_native_result(task, -errno); return task; }
    if (connect(fd, (struct sockaddr*)&addr, size) == 0) {
        task->result_stream = task->stream; task->result_stream->refs++;
        rl_task_native_result(task, 0);
    } else if (errno != EINPROGRESS && errno != EINTR && errno != EALREADY)
        rl_task_native_result(task, -errno);
#else
    (void)address; (void)port; rl_task_native_result(task, -ENOSYS);
#endif
    return task;
}

int32_t rt_async_listener_bind(void* address, int32_t port, int32_t backlog, void** out) {
    *out = NULL;
#if defined(__unix__) || defined(__APPLE__)
    struct sockaddr_storage addr; socklen_t size;
    int error = tcp_address(address, port, &addr, &size);
    if (error || backlog <= 0) return -(error ? error : EINVAL);
    int fd = socket(addr.ss_family, SOCK_STREAM, 0);
    if (fd < 0) return -errno;
    AsyncStream* stream = rl_stream_adopt(fd);
    if (!stream) return -errno;
    int one = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) < 0 ||
        bind(fd, (struct sockaddr*)&addr, size) < 0 || listen(fd, backlog) < 0) {
        error = errno; rl_stream_release(stream); return -error;
    }
    *out = stream; return 0;
#else
    (void)address; (void)port; (void)backlog; return -ENOSYS;
#endif
}

int32_t rt_async_listener_port(void* ptr) {
#if defined(__unix__) || defined(__APPLE__)
    if (!ptr) return -EBADF;
    struct sockaddr_storage addr; socklen_t size = sizeof(addr);
    if (getsockname(((AsyncStream*)ptr)->fd, (struct sockaddr*)&addr, &size) < 0)
        return -errno;
    return addr.ss_family == AF_INET ? ntohs(((struct sockaddr_in*)&addr)->sin_port)
                                    : ntohs(((struct sockaddr_in6*)&addr)->sin6_port);
#else
    (void)ptr; return -ENOSYS;
#endif
}

TaskHandle* rt_async_accept_start(void* ptr) {
    TaskHandle* task = rl_task_new(); task->native_kind = 5; task->stream = ptr;
    if (ptr) task->stream->refs++; else rl_task_native_result(task, -EBADF);
    return task;
}

void* rt_async_take_stream(TaskHandle* task) {
    rt_task_borrow_result(task);
    if ((task->native_kind != 4 && task->native_kind != 5) || !task->result_stream)
        rt_panic("stream result unavailable");
    AsyncStream* stream = task->result_stream; task->result_stream = NULL;
    return stream;
}

void* rt_async_stream_adopt(int32_t fd) { return rl_stream_adopt(fd); }

void* rt_async_stream_pair(void** other) {
    *other = NULL;
#if defined(__unix__) || defined(__APPLE__)
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) < 0) return NULL;
    AsyncStream* a = rl_stream_adopt(fds[0]);
    AsyncStream* b = rl_stream_adopt(fds[1]);
    if (!a || !b) { rl_stream_release(a); rl_stream_release(b); return NULL; }
    *other = b; return a;
#else
    return NULL;
#endif
}

void rt_async_stream_close(void* stream) { rl_stream_release(stream); }

int32_t rt_async_stream_shutdown(void* ptr) {
#if defined(__unix__) || defined(__APPLE__)
    AsyncStream* stream = ptr;
    if (!stream) return -EBADF;
    return shutdown(stream->fd, SHUT_WR) == 0 ? 0 : -errno;
#else
    (void)ptr; return -ENOSYS;
#endif
}

TaskHandle* rt_async_read_start(void* ptr, int32_t limit) {
    TaskHandle* task = rl_task_new();
    task->native_kind = 2; task->stream = ptr;
    if (task->stream) task->stream->refs++;
    if (!ptr || limit < 0) { rl_task_native_result(task, -EINVAL); return task; }
    task->length = limit;
    task->buffer = malloc((size_t)limit + 1);
    if (!task->buffer) { rl_task_native_result(task, -ENOMEM); return task; }
    if (limit == 0) rl_task_native_result(task, 0);
    return task;
}

TaskHandle* rt_async_write_start(void* ptr, void* string) {
    TaskHandle* task = rl_task_new();
    task->native_kind = 3; task->stream = ptr;
    if (task->stream) task->stream->refs++;
    StringVal value = rt_string_obj_value(string);
    if (!ptr || value.len > INT32_MAX) { rl_task_native_result(task, -EINVAL); return task; }
    task->length = (int32_t)value.len;
    task->buffer = malloc((size_t)task->length + 1);
    if (!task->buffer) { rl_task_native_result(task, -ENOMEM); return task; }
    if (value.len) memcpy(task->buffer, value.data, (size_t)value.len);
    if (!task->length) rl_task_native_result(task, 0);
    return task;
}

void* rt_async_read_data(TaskHandle* task) {
    rt_task_borrow_result(task);
    if (task->native_kind != 2) rt_panic("read data requires a read operation");
    char* copy = malloc((size_t)task->offset + 1);
    if (!copy) rt_panic("async read allocation failed");
    if (task->offset) memcpy(copy, task->buffer, (size_t)task->offset);
    copy[task->offset] = 0;
    return rl_string_handle_from_value((StringVal){copy, task->offset});
}

/* ---- Name resolution, datagrams and error text ---- */

#if defined(__unix__) || defined(__APPLE__)
static int rl_socket_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return -1;
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    return 0;
}

static void* rl_address_text(struct sockaddr* addr, int32_t* port) {
    char text[INET6_ADDRSTRLEN] = "";
    if (addr->sa_family == AF_INET) {
        struct sockaddr_in* v4 = (struct sockaddr_in*)addr;
        inet_ntop(AF_INET, &v4->sin_addr, text, sizeof(text));
        if (port) *port = ntohs(v4->sin_port);
    } else if (addr->sa_family == AF_INET6) {
        struct sockaddr_in6* v6 = (struct sockaddr_in6*)addr;
        inet_ntop(AF_INET6, &v6->sin6_addr, text, sizeof(text));
        if (port) *port = ntohs(v6->sin6_port);
    }
    size_t size = strlen(text);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("address allocation failed");
    memcpy(copy, text, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}
#endif

/* A nonblocking datagram socket bound to address:port (port 0: any port). */
int32_t rt_udp_bind(void* address, int32_t port, void** out) {
    *out = NULL;
#if defined(__unix__) || defined(__APPLE__)
    struct sockaddr_storage addr; socklen_t size;
    int error = tcp_address(address, port, &addr, &size);
    if (error) return -error;
    int fd = socket(addr.ss_family, SOCK_DGRAM, 0);
    if (fd < 0) return -errno;
    if (rl_socket_nonblocking(fd) < 0 || bind(fd, (struct sockaddr*)&addr, size) < 0) { error = errno; close(fd); return -error; }
    AsyncStream* stream = malloc(sizeof(*stream));
    if (!stream) { close(fd); rt_panic("socket allocation failed"); }
    stream->fd = fd; stream->refs = 1;
    *out = stream; return 0;
#else
    (void)address; (void)port; return -ENOSYS;
#endif
}

TaskHandle* rt_udp_send_start(void* ptr, void* data, void* address, int32_t port) {
    TaskHandle* task = rl_task_new(); task->native_kind = 6; task->stream = ptr;
    if (ptr) task->stream->refs++;
#if defined(__unix__) || defined(__APPLE__)
    StringVal value = rt_string_obj_value(data);
    struct sockaddr_storage addr; socklen_t size;
    int error = tcp_address(address, port, &addr, &size);
    if (!ptr || error || value.len > 65507) { rl_task_native_result(task, -(error ? error : (ptr ? EMSGSIZE : EBADF))); return task; }
    memcpy(task->peer, &addr, size); task->peer_size = (int32_t)size;
    task->length = (int32_t)value.len;
    task->buffer = malloc((size_t)task->length + 1);
    if (!task->buffer) { rl_task_native_result(task, -ENOMEM); return task; }
    if (value.len) memcpy(task->buffer, value.data, (size_t)value.len);
#else
    (void)data; (void)address; (void)port; rl_task_native_result(task, -ENOSYS);
#endif
    return task;
}

TaskHandle* rt_udp_receive_start(void* ptr, int32_t limit) {
    TaskHandle* task = rl_task_new(); task->native_kind = 7; task->stream = ptr;
    if (ptr) task->stream->refs++;
    if (!ptr || limit <= 0) { rl_task_native_result(task, -EINVAL); return task; }
    task->length = limit;
    task->buffer = malloc((size_t)limit + 1);
    if (!task->buffer) rl_task_native_result(task, -ENOMEM);
    return task;
}

void* rt_udp_received_data(TaskHandle* task) {
    rt_task_borrow_result(task);
    if (task->native_kind != 7) rt_panic("datagram data requires a receive operation");
    char* copy = malloc((size_t)task->offset + 1);
    if (!copy) rt_panic("datagram allocation failed");
    if (task->offset) memcpy(copy, task->buffer, (size_t)task->offset);
    copy[task->offset] = 0;
    return rl_string_handle_from_value((StringVal){copy, task->offset});
}

void* rt_udp_received_address(TaskHandle* task, int32_t* port) {
#if defined(__unix__) || defined(__APPLE__)
    return rl_address_text((struct sockaddr*)task->peer, port);
#else
    (void)task; *port = 0; return rl_string_handle_from_value((StringVal){NULL, 0});
#endif
}

/* The local port of a bound socket. */
int32_t rt_socket_port(void* ptr) { return rt_async_listener_port(ptr); }

/* The operating system's text for an errno value. */
void* rt_os_error_message(int32_t code) {
    const char* message = strerror(code);
    size_t size = strlen(message);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("message allocation failed");
    memcpy(copy, message, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

int32_t rt_errno_host_unreachable(void) { return EHOSTUNREACH; }

/* ---- Name resolution on a helper thread ----
 *
 * getaddrinfo blocks, so it runs on a detached thread that writes its result
 * into a job and then a byte into a pipe; the scheduler polls the pipe's read
 * end like any socket. The job is shared: whichever of the task and the thread
 * finishes with it last frees it, so a cancelled lookup cannot touch freed
 * memory. The thread uses no Rolang objects. */
#if defined(__unix__) || defined(__APPLE__)
#include <pthread.h>
typedef struct ResolveJob {
    pthread_mutex_t lock;
    int owners;                /* task and thread */
    char host[256];
    int error;                 /* getaddrinfo status, 0 on success */
    char* text;                /* addresses, one per line, or the error message */
    size_t text_len;
    int notify;                /* pipe write end, owned by the thread */
} ResolveJob;

static void resolve_job_release(ResolveJob* job) {
    pthread_mutex_lock(&job->lock);
    int left = --job->owners;
    pthread_mutex_unlock(&job->lock);
    if (left) return;
    pthread_mutex_destroy(&job->lock);
    free(job->text);
    free(job);
}

static ResolveJob* resolve_job_of(TaskHandle* task) {
    ResolveJob* job; memcpy(&job, task->peer, sizeof(job)); return job;
}

static char* resolve_copy(const char* text, size_t* size) {
    *size = strlen(text);
    char* copy = malloc(*size + 1);
    if (copy) memcpy(copy, text, *size + 1);
    return copy;
}

static void* resolve_thread(void* argument) {
    ResolveJob* job = argument;
    struct addrinfo hints; memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* list = NULL;
    int status = getaddrinfo(job->host, NULL, &hints, &list);
    if (status != 0) {
        job->error = status;
        job->text = resolve_copy(gai_strerror(status), &job->text_len);
    } else {
        size_t capacity = 64, used = 0;
        char* out = malloc(capacity);
        for (int family = 0; out && family < 2; family++) {
            for (struct addrinfo* item = list; item; item = item->ai_next) {
                int wanted = family == 0 ? AF_INET : AF_INET6;
                if (item->ai_family != wanted) continue;
                char text[INET6_ADDRSTRLEN] = "";
                if (wanted == AF_INET) inet_ntop(AF_INET, &((struct sockaddr_in*)item->ai_addr)->sin_addr, text, sizeof(text));
                else inet_ntop(AF_INET6, &((struct sockaddr_in6*)item->ai_addr)->sin6_addr, text, sizeof(text));
                size_t size = strlen(text);
                if (!size) continue;
                int seen = 0;
                for (size_t at = 0; at < used;) {
                    size_t end = at; while (end < used && out[end] != '\n') end++;
                    if (end - at == size && memcmp(out + at, text, size) == 0) { seen = 1; break; }
                    at = end + 1;
                }
                if (seen) continue;
                while (used + size + 2 > capacity) { capacity *= 2; char* grown = realloc(out, capacity); if (!grown) { free(out); out = NULL; break; } out = grown; }
                if (!out) break;
                if (used) out[used++] = '\n';
                memcpy(out + used, text, size); used += size;
            }
        }
        freeaddrinfo(list);
        if (out) { out[used] = 0; job->text = out; job->text_len = used; }
        else { job->error = EAI_MEMORY; job->text = resolve_copy("out of memory", &job->text_len); }
    }
    char byte = 1;
    ssize_t written = write(job->notify, &byte, 1);
    (void)written;
    close(job->notify);
    resolve_job_release(job);
    return NULL;
}
#endif

/* Starts resolving `host`; numeric addresses complete at once. The task's
 * result is 0, or -1 when the resolver failed (see rt_net_resolve_result). */
TaskHandle* rt_net_resolve_start(void* host_string) {
    TaskHandle* task = rl_task_new(); task->native_kind = 8;
#if defined(__unix__) || defined(__APPLE__)
    StringVal host = rt_string_obj_value(host_string);
    ResolveJob* job = calloc(1, sizeof(*job));
    if (!job) rt_panic("resolver allocation failed");
    pthread_mutex_init(&job->lock, NULL);
    job->owners = 1;
    memcpy(task->peer, &job, sizeof(job));
    if (host.len <= 0 || host.len >= (int64_t)sizeof(job->host) || memchr(host.data, 0, (size_t)host.len)) {
        job->error = EAI_NONAME; job->text = resolve_copy("invalid host name", &job->text_len);
        rl_task_native_result(task, -1); return task;
    }
    memcpy(job->host, host.data, (size_t)host.len);
    unsigned char numeric[sizeof(struct in6_addr)];
    if (inet_pton(AF_INET, job->host, numeric) == 1 || inet_pton(AF_INET6, job->host, numeric) == 1) {
        job->text = resolve_copy(job->host, &job->text_len);
        rl_task_native_result(task, 0); return task;
    }
    int fds[2];
    if (pipe(fds) < 0) { job->error = EAI_SYSTEM; job->text = resolve_copy(strerror(errno), &job->text_len); rl_task_native_result(task, -1); return task; }
    (void)fcntl(fds[0], F_SETFD, FD_CLOEXEC); (void)fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    AsyncStream* stream = malloc(sizeof(*stream));
    if (!stream) rt_panic("resolver allocation failed");
    stream->fd = fds[0]; stream->refs = 1; task->stream = stream;
    job->notify = fds[1];
    job->owners = 2;
    pthread_t thread;
    if (pthread_create(&thread, NULL, resolve_thread, job) != 0) {
        job->owners = 1; close(fds[1]);
        job->error = EAI_SYSTEM; job->text = resolve_copy("cannot start the resolver thread", &job->text_len);
        rl_task_native_result(task, -1); return task;
    }
    pthread_detach(thread);
#else
    (void)host_string; rl_task_native_result(task, -1);
#endif
    return task;
}

static void rl_resolve_ready(TaskHandle* task) {
#if defined(__unix__) || defined(__APPLE__)
    char byte;
    ssize_t got = read(task->stream->fd, &byte, 1);
    (void)got;
    rl_task_native_result(task, resolve_job_of(task)->error ? -1 : 0);
#else
    (void)task;
#endif
}

void* rt_net_resolve_result(TaskHandle* task, int32_t* error) {
    rt_task_borrow_result(task);
#if defined(__unix__) || defined(__APPLE__)
    ResolveJob* job = resolve_job_of(task);
    *error = job->error;
    char* copy = malloc(job->text_len + 1);
    if (!copy) rt_panic("resolver allocation failed");
    memcpy(copy, job->text ? job->text : "", job->text_len + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)job->text_len});
#else
    *error = -1; return rl_string_handle_from_value((StringVal){NULL, 0});
#endif
}

void rl_resolve_release(TaskHandle* task) {
#if defined(__unix__) || defined(__APPLE__)
    resolve_job_release(resolve_job_of(task));
#else
    (void)task;
#endif
}
