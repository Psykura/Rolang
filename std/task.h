#ifndef ROLANG_STD_TASK_H
#define ROLANG_STD_TASK_H

#include "../runtime/abi.h"
#include "string.h"
#include "../runtime/task.h"


int32_t rt_task_cancel(TaskHandle* task);
void rt_task_gc_trace(void* payload, GCTraceCb cb, void* ctx);
void rt_task_destroy(TaskHandle* task);
int32_t rt_task_poll(TaskHandle* task);
int32_t rt_task_cancelled(TaskHandle* task);
void* rt_task_join(TaskHandle* task);
void rt_task_wait_done(TaskHandle* task);
TaskHandle* rt_async_sleep_start(int64_t ms);

#endif /* ROLANG_STD_TASK_H */
