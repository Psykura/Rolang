#ifndef ROLANG_STD_SUBPROCESS_H
#define ROLANG_STD_SUBPROCESS_H

#include "../runtime/abi.h"
#include "string.h"
#include "vec.h"
#include "../runtime/task.h"

void* rt_child_spawn(void* program, void* arguments, void* environment, int32_t cleared,
                     void* directory, int32_t in_mode, int32_t out_mode, int32_t err_mode,
                     void** input, void** output, void** errors, int32_t* error);
int32_t rt_child_pid(void* child);
void rt_child_release(void* child);
TaskHandle* rt_child_wait_start(void* child);
int32_t rt_child_status(void* child, int32_t* signal);
int32_t rt_child_kill(void* child, int32_t signal);

#endif /* ROLANG_STD_SUBPROCESS_H */
