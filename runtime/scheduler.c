#include "platform.h"
#include "api.h"
#include "../std/task.h"
#include "../std/async_io.h"

/* Async scheduler: ready tasks rotate FIFO; suspended tasks are parked on
 * dependencies, monotonic deadlines, or socket readiness. No worker threads. */
#include <errno.h>
#include <limits.h>
#include <time.h>
#if defined(__unix__) || defined(__APPLE__)
#include <poll.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <fcntl.h>
#endif

static TaskHandle *task_head = NULL, *task_tail = NULL, *current_task = NULL;
static int64_t task_live_count = 0;
void rl_task_release(TaskHandle* task);
void rl_task_step(void);

int64_t rl_task_now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) rt_panic("monotonic clock failed");
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
static void task_append(TaskHandle* task) {
    task->next = NULL;
    if (task_tail) task_tail->next = task; else task_head = task;
    task_tail = task;
}
TaskHandle* rl_task_new(void) {
    TaskHandle* task = (TaskHandle*)calloc(1, sizeof(TaskHandle));
    if (!task) rt_panic("async task allocation failed");
    task->refs = 2; /* caller + scheduler */
    task_live_count++;
    task_append(task);
    return task;
}
int64_t rt_task_live_count(void) { return task_live_count; }
void* rt_frame_alloc(int64_t size) { return malloc((size_t)size); }
void rt_frame_free(void* frame) { free(frame); }
TaskHandle* rt_task_spawn(void (*resume_fn)(void*), void* frame) {
    TaskHandle* task = rl_task_new();
    task->frame = frame;
    task->resume_fn = resume_fn;
    /* The active scheduler is a GC root independent of the source Task. */
    if (frame) rt_obj_retain(frame);
    return task;
}
void rl_task_clear_dependency(TaskHandle* task, int cancelling);

void rl_task_clear_dependency(TaskHandle* task, int cancelling) {
    TaskHandle* child = task->dependency;
    if (!child) return;
    task->dependency = NULL;
    if (task->owns_dependency) {
        /* The generated await's result extraction normally consumes this
         * owner. Cancellation must do that cleanup instead. */
        if (cancelling) { rt_task_cancel(child); rl_task_release(child); }
    } else rl_task_release(child);
    task->owns_dependency = 0;
}
void rl_task_release(TaskHandle* task) {
    if (!task || --task->refs) return;
    if (task->result_kind == RT_TASK_RESULT_BOX) free(task->result);
    else if (task->result_kind == RT_TASK_RESULT_HEAP_REF) rt_obj_release(task->result);
    rl_stream_release(task->stream);
    rl_stream_release(task->result_stream);
    free(task->buffer);
    task_live_count--;
    free(task);
}

void rt_task_complete_owned(TaskHandle* task, void* result, int32_t kind) {
    if (!task || task->cancelled) {
        if (kind == RT_TASK_RESULT_BOX) free(result);
        else if (kind == RT_TASK_RESULT_HEAP_REF) rt_obj_release(result);
        return;
    }
    task->result = result;
    task->result_kind = kind;
    task->completed = 1;
}
void rt_task_complete(TaskHandle* task, void* result) {
    rt_task_complete_owned(task, result, RT_TASK_RESULT_NONE);
}
void rt_task_wait_on(TaskHandle* child, int32_t owned) {
    if (!current_task) rt_panic("task suspension outside scheduler");
    if (!child || child == current_task) rt_panic("task cannot await itself or a null handle");
    for (TaskHandle* p = child; p; p = p->dependency)
        if (p == current_task) rt_panic("cyclic task dependency");
    if (current_task->dependency) rt_panic("task already has a dependency");
    current_task->dependency = child;
    current_task->owns_dependency = owned;
    if (!owned) child->refs++;
}
void rt_task_yield(void) { /* Resume functions return to the scheduler. */ }
void rl_task_retire_completed(void) {
    TaskHandle **link = &task_head, *prev = NULL;
    while (*link) {
        TaskHandle* task = *link;
        if (!task->completed || task->running) { prev = task; link = &task->next; continue; }
        *link = task->next;
        if (task_tail == task) task_tail = prev;
        rl_task_clear_dependency(task, task->cancelled);
        if (task->frame) {
            void* frame = task->frame;
            task->frame = NULL;
            rt_obj_release(frame); /* scheduler GC root */
            rt_obj_release(frame); /* transferred frame owner */
        }
        rl_task_release(task); /* scheduler handle owner */
        /* Releasing a frame can cancel other tasks. Restart to retire those
         * too before blocking in poll. */
        link = &task_head; prev = NULL;
    }
}
void rl_task_native_result(TaskHandle* task, int32_t result) {
    int32_t* box = malloc(sizeof(int32_t));
    if (!box) rt_panic("async result allocation failed");
    *box = result;
    rt_task_complete_owned(task, box, RT_TASK_RESULT_BOX);
}
AsyncStream* rl_stream_adopt(int fd);

static void task_poll_events(int may_block) {
#if defined(__unix__) || defined(__APPLE__)
    size_t count = 0;
    int timeout = may_block ? -1 : 0;
    int64_t now = rl_task_now_ms();
    for (TaskHandle* t = task_head; t; t = t->next) {
        if (t->completed || t->running) continue;
        if (t->native_kind == 1) {
            int64_t delay = t->deadline - now;
            if (delay <= 0) { rl_task_native_result(t, 0); timeout = 0; }
            else if (may_block && (timeout < 0 || delay < timeout))
                timeout = delay > INT_MAX ? INT_MAX : (int)delay;
        } else if (t->native_kind >= 2) count++;
    }
    if (!count && timeout < 0) rt_panic("async scheduler deadlock: no runnable tasks or I/O");
    struct pollfd* fds = count ? calloc(count, sizeof(*fds)) : NULL;
    TaskHandle** tasks = count ? malloc(count * sizeof(*tasks)) : NULL;
    if (count && (!fds || !tasks)) rt_panic("async poll allocation failed");
    size_t i = 0;
    for (TaskHandle* t = task_head; t; t = t->next) {
        if (t->completed || t->running || t->native_kind < 2) continue;
        tasks[i] = t; fds[i].fd = t->stream->fd;
        fds[i].events = (t->native_kind == 2 || t->native_kind == 5 || t->native_kind == 7) ? POLLIN : POLLOUT; i++;
    }
    int n = poll(fds, (nfds_t)count, timeout);
    if (n < 0 && errno != EINTR) rt_panic("async poll failed");
    if (n > 0) for (i = 0; i < count; i++) {
        if (fds[i].revents & POLLNVAL) rl_task_native_result(tasks[i], -EBADF);
        else if (fds[i].revents) rl_async_ready(tasks[i]);
    }
    free(tasks); free(fds);
#else
    (void)may_block;
    rt_panic("async I/O requires POSIX poll support");
#endif
}
void rl_task_step(void) {
    rl_task_retire_completed();
    if (!task_head) return;
    /* Nonblocking polling on every turn prevents CPU-ready tasks from starving I/O. */
    task_poll_events(0);
    TaskHandle **link = &task_head, *prev = NULL;
    while (*link) {
        TaskHandle* t = *link;
        if (!t->completed && !t->running && !t->native_kind &&
            (!t->dependency || t->dependency->completed)) {
            *link = t->next;
            if (task_tail == t) task_tail = prev;
            task_append(t);
            rl_task_clear_dependency(t, 0);
            TaskHandle* saved = current_task;
            current_task = t; t->running = 1;
            t->resume_fn(t->frame);
            t->running = 0; current_task = saved;
            rl_task_retire_completed();
            return;
        }
        prev = t; link = &t->next;
    }
    rl_task_retire_completed();
    if (task_head) task_poll_events(1);
    rl_task_retire_completed();
}

void* rt_task_borrow_result(TaskHandle* task) {
    if (!task || !task->completed) rt_panic("result of pending task");
    if (task->cancelled) rt_panic("await of cancelled task; use Task.wait() to inspect cancellation");
    return task->result;
}
void* rt_task_take_result(TaskHandle* task) {
    void* result = rt_task_borrow_result(task);
    task->result = NULL; task->result_kind = RT_TASK_RESULT_NONE;
    return result;
}

void rt_scheduler_run(void) { while (task_head) rl_task_step(); }
void rt_scheduler_shutdown(void) {
    for (TaskHandle* t = task_head; t; t = t->next) rt_task_cancel(t);
    rl_task_retire_completed();
}

void* rl_string_handle_from_value(StringVal s);
