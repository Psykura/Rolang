#include "platform.h"
#include "api.h"
#include "../std/task.h"
#include "../std/async_io.h"
#include "../std/async_fs.h"
#include "../std/parallel.h"

/* Async scheduler, one per thread (thread-local in a ROLANG_THREADED runtime).
 *
 * Runnable frame tasks rotate FIFO on the ready queue. A task that awaits
 * another joins that task's waiters and returns to the ready queue when it
 * finishes. Native tasks (timers, socket and pipe readiness, file jobs,
 * parallel jobs) sit on the native list, which is all a poll looks at.
 * Finished tasks queue for retirement. Each step therefore costs time in
 * the work it does, not in the number of tasks alive. Every queue
 * membership holds a task reference, so a queued task is never freed. */
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

static RL_TLS TaskHandle *task_head = NULL, *task_tail = NULL, *current_task = NULL;
static RL_TLS TaskHandle *ready_head = NULL, *ready_tail = NULL;
static RL_TLS TaskHandle *native_head = NULL;
static RL_TLS TaskHandle *retire_head = NULL, *retire_tail = NULL;
static RL_TLS int64_t task_live_count = 0;
static RL_TLS int64_t native_count = 0;
/* A thread's wake pipe (parallel jobs), polled with the native tasks' descriptors. */
static RL_TLS int task_wake_fd = -1;
void rl_task_set_wake_fd(int fd) { task_wake_fd = fd; }
int rl_task_has_tasks(void) { return task_head != NULL; }
void rl_task_release(TaskHandle* task);
void rl_task_step(void);

int64_t rl_task_now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) rt_panic("monotonic clock failed");
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

/* ---- Queues ---- */

static void ready_push(TaskHandle* task) {
    if (task->in_ready || task->completed) return;
    task->in_ready = 1; task->refs++;
    task->ready_next = NULL;
    if (ready_tail) ready_tail->ready_next = task; else ready_head = task;
    ready_tail = task;
}

/* The next queued task, with the queue's reference passed to the caller. */
static TaskHandle* ready_pop(void) {
    TaskHandle* task = ready_head;
    if (!task) return NULL;
    ready_head = task->ready_next;
    if (!ready_head) ready_tail = NULL;
    task->ready_next = NULL; task->in_ready = 0;
    return task;
}

static void native_add(TaskHandle* task) {
    if (task->in_native) return;
    task->in_native = 1; task->refs++;
    task->native_prev = NULL; task->native_next = native_head;
    if (native_head) native_head->native_prev = task;
    native_head = task;
    native_count++;
}

static void native_remove(TaskHandle* task) {
    if (!task->in_native) return;
    if (task->native_prev) task->native_prev->native_next = task->native_next; else native_head = task->native_next;
    if (task->native_next) task->native_next->native_prev = task->native_prev;
    task->native_next = task->native_prev = NULL; task->in_native = 0;
    native_count--;
    rl_task_release(task);
}

static void retire_push(TaskHandle* task) {
    if (task->in_retire) return;
    task->in_retire = 1; task->refs++;
    task->retire_next = NULL;
    if (retire_tail) retire_tail->retire_next = task; else retire_head = task;
    retire_tail = task;
}

/* Tasks waiting on `task` become runnable. */
static void wake_waiters(TaskHandle* task) {
    TaskHandle* waiter = task->waiters;
    task->waiters = NULL;
    while (waiter) {
        TaskHandle* next = waiter->wait_next;
        waiter->wait_next = NULL;
        ready_push(waiter);
        rl_task_release(waiter);   /* the waiters list's reference */
        waiter = next;
    }
}

/* A task finished (completed or cancelled): wake its waiters, queue its retirement. */
void rl_task_finished(TaskHandle* task) {
    wake_waiters(task);
    retire_push(task);
}

/* ---- Tasks ---- */

TaskHandle* rl_task_new(void) {
    TaskHandle* task = (TaskHandle*)calloc(1, sizeof(TaskHandle));
    if (!task) rt_panic("async task allocation failed");
    task->refs = 2; /* caller + scheduler */
    task_live_count++;
    task->next = NULL; task->all_prev = task_tail;
    if (task_tail) task_tail->next = task; else task_head = task;
    task_tail = task;
    /* Natives set native_kind after this returns; the first look moves them to the native list. */
    ready_push(task);
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
    /* Tasks still listed as waiting on this one (only possible once nothing awaits it). */
    TaskHandle* waiter = task->waiters;
    task->waiters = NULL;
    while (waiter) { TaskHandle* next = waiter->wait_next; waiter->wait_next = NULL; rl_task_release(waiter); waiter = next; }
    if (task->result_kind == RT_TASK_RESULT_BOX) free(task->result);
    else if (task->result_kind == RT_TASK_RESULT_HEAP_REF) rt_obj_release(task->result);
    if (task->native_kind == 8) rl_resolve_release(task);
    if (task->native_kind == 12) rl_fs_release(task);
    if (task->native_kind == 13) rl_parallel_release(task);
    if (task->native_kind == 14) rl_channel_wait_release(task);
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
    rl_task_finished(task);
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

/* Releases finished tasks that are not running. Releasing a frame can cancel
 * more tasks; those join the queue and retire in the same call. */
void rl_task_retire_completed(void) {
    TaskHandle* deferred = NULL;
    while (retire_head) {
        TaskHandle* task = retire_head;
        retire_head = task->retire_next;
        if (!retire_head) retire_tail = NULL;
        task->retire_next = NULL; task->in_retire = 0;
        if (task->running) {
            /* Finished but still on the stack (completing itself): retire after it returns. */
            task->retire_next = deferred; deferred = task; continue;
        }
        if (task->in_native) native_remove(task);
        /* Unlink from the all list (the scheduler's own reference). */
        if (task->all_prev || task_head == task) {
            if (task->all_prev) task->all_prev->next = task->next; else task_head = task->next;
            if (task->next) task->next->all_prev = task->all_prev; else task_tail = task->all_prev;
            task->next = task->all_prev = NULL;
            rl_task_clear_dependency(task, task->cancelled);
            if (task->frame) {
                void* frame = task->frame;
                task->frame = NULL;
                rt_obj_release(frame); /* scheduler GC root */
                rt_obj_release(frame); /* transferred frame owner */
            }
            rl_task_release(task); /* scheduler handle owner */
        }
        rl_task_release(task);     /* the retire queue's reference */
    }
    /* With every task retired, queued entries are all finished tasks: drop them. */
    if (!task_head && !deferred) {
        TaskHandle* stale;
        while ((stale = ready_pop())) rl_task_release(stale);
    }
    while (deferred) {
        TaskHandle* next = deferred->retire_next;
        deferred->retire_next = NULL;
        /* Requeue keeping the reference taken when it was first queued. */
        deferred->in_retire = 1;
        if (retire_tail) retire_tail->retire_next = deferred; else retire_head = deferred;
        retire_tail = deferred;
        deferred = next;
    }
}
void rl_task_native_result(TaskHandle* task, int32_t result) {
    int32_t* box = malloc(sizeof(int32_t));
    if (!box) rt_panic("async result allocation failed");
    *box = result;
    rt_task_complete_owned(task, box, RT_TASK_RESULT_BOX);
}
AsyncStream* rl_stream_adopt(int fd);

/* Waits for native tasks (up to the nearest timer, or not at all) and
 * completes those that are ready. */
static void task_poll_events(int may_block) {
#if defined(__unix__) || defined(__APPLE__)
    size_t count = 0;
    int timeout = may_block ? -1 : 0;
    int64_t now = rl_task_now_ms();
    for (TaskHandle* t = native_head; t; ) {
        TaskHandle* next = t->native_next;
        if (t->completed) { native_remove(t); t = next; continue; }
        if (t->native_kind == 1) {
            int64_t delay = t->deadline - now;
            if (delay <= 0) { rl_task_native_result(t, 0); timeout = 0; }
            else if (may_block && (timeout < 0 || delay < timeout))
                timeout = delay > INT_MAX ? INT_MAX : (int)delay;
        } else if (t->stream) count++;
        t = next;
    }
    if (!count && task_wake_fd < 0) {
        if (timeout < 0 && may_block) rt_panic("async scheduler deadlock: no runnable tasks or I/O");
        if (timeout > 0) { struct timespec pause = { timeout / 1000, (long)(timeout % 1000) * 1000000 }; nanosleep(&pause, NULL); }
        return;
    }
    /* Native tasks' descriptors, then the wake pipe. */
    size_t total = count + (task_wake_fd >= 0 ? 1 : 0);
    struct pollfd* fds = calloc(total, sizeof(*fds));
    TaskHandle** tasks = count ? malloc(count * sizeof(*tasks)) : NULL;
    if (!fds || (count && !tasks)) rt_panic("async poll allocation failed");
    size_t i = 0;
    for (TaskHandle* t = native_head; t; t = t->native_next) {
        if (t->completed || t->native_kind < 2 || !t->stream) continue;
        tasks[i] = t; t->refs++; fds[i].fd = t->stream->fd;
        fds[i].events = (t->native_kind == 2 || t->native_kind == 5 || t->native_kind == 7 || t->native_kind == 8 || t->native_kind == 9 || t->native_kind == 11 || t->native_kind == 12) ? POLLIN : POLLOUT; i++;
    }
    if (task_wake_fd >= 0) { fds[count].fd = task_wake_fd; fds[count].events = POLLIN; }
    int n = poll(fds, (nfds_t)total, timeout);
    if (n < 0 && errno != EINTR) rt_panic("async poll failed");
    if (n > 0) for (i = 0; i < count; i++) {
        if (tasks[i]->completed) continue;
        if (fds[i].revents & POLLNVAL) rl_task_native_result(tasks[i], -EBADF);
        else if (fds[i].revents) rl_async_ready(tasks[i]);
    }
    /* Finished parallel jobs (and, on a worker, new ones) arrive through the wake pipe. */
    if (n > 0 && task_wake_fd >= 0 && fds[count].revents) rl_parallel_wake();
    for (i = 0; i < count; i++) rl_task_release(tasks[i]);
    free(tasks); free(fds);
#else
    (void)may_block;
    rt_panic("async I/O requires POSIX poll support");
#endif
}

/* After a frame task's resume returns: it finished, waits on its dependency,
 * or yielded and runs again later. */
static void task_after_resume(TaskHandle* task) {
    if (task->completed) return;
    TaskHandle* child = task->dependency;
    if (child && !child->completed) {
        task->refs++;   /* the waiters list's reference */
        task->wait_next = child->waiters;
        child->waiters = task;
        return;
    }
    ready_push(task);
}

static RL_TLS int64_t steps_since_poll = 0;

/* Runs one ready task, or (with none ready) waits for I/O, timers or jobs. */
void rl_task_step(void) {
    rl_task_retire_completed();
    if (!task_head) return;
    /* Nonblocking polls between tasks keep CPU-bound tasks from starving I/O. */
    if (native_count > 0 && ++steps_since_poll >= 16) { steps_since_poll = 0; task_poll_events(0); }
    TaskHandle* t;
    while ((t = ready_pop())) {
        if (t->completed || t->running) { rl_task_release(t); continue; }
        if (t->native_kind) { native_add(t); rl_task_release(t); continue; }
        if (t->dependency && !t->dependency->completed) { task_after_resume(t); rl_task_release(t); continue; }
        rl_task_clear_dependency(t, 0);
        TaskHandle* saved = current_task;
        current_task = t; t->running = 1;
        t->resume_fn(t->frame);
        t->running = 0; current_task = saved;
        task_after_resume(t);
        if (t->completed) retire_push(t);
        rl_task_release(t);   /* the ready queue's reference */
        rl_task_retire_completed();
        return;
    }
    rl_task_retire_completed();
    if (task_head) { steps_since_poll = 0; task_poll_events(1); }
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
