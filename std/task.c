#include "../runtime/platform.h"
#include "task.h"
#include "../runtime/api.h"

TaskHandle* rt_async_sleep_start(int64_t ms) {
    TaskHandle* task = rl_task_new();
    task->native_kind = 1;
    int64_t now = rl_task_now_ms();
    task->deadline = ms <= 0 ? now : (ms > INT64_MAX - now ? INT64_MAX : now + ms);
    return task;
}

void rl_task_finished(TaskHandle* task);

int32_t rt_task_cancel(TaskHandle* task) {
    if (!task || task->completed) return 0;
    task->cancelled = task->completed = 1;
    rl_task_clear_dependency(task, 1);
    rl_task_finished(task);
    return 1;
}

int32_t rt_task_cancelled(TaskHandle* task) { return task && task->cancelled; }

void rt_task_destroy(TaskHandle* task) {
    if (!task) return;
    if (!task->detached) rt_task_cancel(task);
    rl_task_release(task);
}

/* The task keeps running when its Task is released. */
void rt_task_detach(TaskHandle* task) { if (task) task->detached = 1; }

void rt_task_gc_trace(void* payload, GCTraceCb cb, void* ctx) {
    if (!payload || !cb) return;
    TaskHandle* task = *(TaskHandle**)payload;
    if (!task) return;
    if (task->frame) cb(task->frame, ctx);
    if (task->result_kind == RT_TASK_RESULT_HEAP_REF && task->result)
        cb(task->result, ctx);
}

void* rt_task_join(TaskHandle* task) {
    if (!task) rt_panic("join of null task");
    if (task->running) rt_panic("join of running task");
    while (!task->completed) rl_task_step();
    rl_task_retire_completed();
    return task->result;
}

int32_t rt_task_poll(TaskHandle* task) { return !task || task->completed; }

void rt_task_wait_done(TaskHandle* task) { rt_task_join(task); }
