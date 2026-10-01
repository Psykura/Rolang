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

void rl_async_ready(TaskHandle* task) {
#if defined(__unix__) || defined(__APPLE__)
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
