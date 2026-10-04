#ifndef ROLANG_STD_PARALLEL_H
#define ROLANG_STD_PARALLEL_H

#include "../runtime/abi.h"
#include "string.h"
#include "../runtime/task.h"

void* rt_send_buffer_new(void);
void rt_send_buffer_free(void* buffer);
void rt_send_put_i64(void* buffer, int64_t value);
void rt_send_put_f64(void* buffer, double value);
void rt_send_put_string(void* buffer, void* string);
void rt_send_enter(void* buffer);
void rt_send_leave(void* buffer);
int64_t rt_send_get_i64(void* buffer);
double rt_send_get_f64(void* buffer);
void* rt_send_get_string(void* buffer);
int32_t rt_parallel_workers(void);
TaskHandle* rt_parallel_submit(void* start_closure, void* arguments);
void* rt_parallel_arguments(void* job);
void rt_parallel_complete(void* job, void* result);
void* rt_parallel_result(TaskHandle* task);
int32_t rt_parallel_on_worker(void);
ROLANG_INTERNAL void rl_parallel_ready(TaskHandle* task);
ROLANG_INTERNAL void rl_parallel_release(TaskHandle* task);
ROLANG_INTERNAL void rl_task_set_wake_fd(int fd);
ROLANG_INTERNAL void rl_parallel_wake(void);

#endif /* ROLANG_STD_PARALLEL_H */
