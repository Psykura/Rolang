#ifndef ROLANG_STD_ASYNC_FS_H
#define ROLANG_STD_ASYNC_FS_H

#include "../runtime/abi.h"
#include "string.h"
#include "../runtime/task.h"

TaskHandle* rt_fs_start(int32_t op, void* path, void* other, void* input, int64_t limit, int64_t flags);
ROLANG_INTERNAL void rl_fs_ready(TaskHandle* task);
ROLANG_INTERNAL void rl_fs_release(TaskHandle* task);
int32_t rt_fs_error(TaskHandle* task);
void* rt_fs_output(TaskHandle* task);
int64_t rt_fs_value(TaskHandle* task, int32_t index);

#endif /* ROLANG_STD_ASYNC_FS_H */
