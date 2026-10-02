#ifndef ROLANG_RUNTIME_API_H
#define ROLANG_RUNTIME_API_H

#include "abi.h"
#include "task.h"
void* rt_alloc(int64_t size, int64_t align);
void rt_free(void* ptr);
void rt_register_module_types(TypeDescriptor* descriptors, int32_t count,
                              FieldDescriptor* fields, int32_t field_count,
                              const char** keys);
void* rt_obj_alloc(int64_t payload_size, int64_t align, uint64_t type_id);
void* rt_obj_alloc_noinit(int64_t payload_size, int64_t align, uint64_t type_id);
void rt_obj_retain(void* ptr);
void rt_obj_release(void* ptr);
void rt_obj_release_slow(void* ptr);
void* rt_obj_clone(void* ptr);
void rt_gc_collect(void);
int64_t rt_obj_alloc_count(void);
int64_t rt_obj_live_count(void);
int64_t rt_gc_cycle_count(void);
__attribute__((noreturn))
void rt_panic(const char* ctx);
__attribute__((noreturn)) void rt_panic_finish(void);
__attribute__((noreturn))
void rt_panic_index_out_of_bounds(int64_t index, int64_t len);
__attribute__((noreturn))
void rt_panic_divide_by_zero(void);
__attribute__((noreturn))
void rt_panic_remainder_by_zero(void);
__attribute__((noreturn))
void rt_panic_invalid_cast(void);
ROLANG_INTERNAL int64_t rl_task_now_ms(void);
ROLANG_INTERNAL TaskHandle* rl_task_new(void);
int64_t rt_task_live_count(void);
void* rt_frame_alloc(int64_t size);
void rt_frame_free(void* frame);
TaskHandle* rt_task_spawn(void (*resume_fn)(void*), void* frame);
ROLANG_INTERNAL void rl_task_clear_dependency(TaskHandle* task, int cancelling);
ROLANG_INTERNAL void rl_task_release(TaskHandle* task);
void rt_task_complete_owned(TaskHandle* task, void* result, int32_t kind);
void rt_task_complete(TaskHandle* task, void* result);
void rt_task_wait_on(TaskHandle* child, int32_t owned);
void rt_task_yield(void);
ROLANG_INTERNAL void rl_task_retire_completed(void);
ROLANG_INTERNAL void rl_task_native_result(TaskHandle* task, int32_t result);
ROLANG_INTERNAL void rl_task_step(void);
void* rt_task_borrow_result(TaskHandle* task);
void* rt_task_take_result(TaskHandle* task);
void rt_scheduler_run(void);
void rt_scheduler_shutdown(void);

#endif /* ROLANG_RUNTIME_API_H */
