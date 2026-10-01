#ifndef ROLANG_STD_PROCESS_H
#define ROLANG_STD_PROCESS_H

#include "../runtime/abi.h"
#include "string.h"


ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);
int32_t rt_args_count(void);
StringVal rt_args_get(int32_t index);
StringVal rt_env_get(StringVal name);
int32_t rt_env_set(StringVal name, StringVal value);
int32_t rt_process_system(StringVal cmd);
int32_t rt_process_run_argv(void* argv_vec);
int32_t rt_process_run_argv_log(void* argv_vec, void* log_obj);
__attribute__((noreturn))
void rt_exit(int32_t code);
StringVal rt_stdin_read_line(void);
StringVal rt_stdin_read_all(void);
void* rt_args_get_handle(int32_t index);
void* rt_env_get_handle(void* name);
int32_t rt_env_set_string(void* name, void* value);
int32_t rt_process_system_string(void* cmd);
void* rt_stdin_read_line_handle(void);
void* rt_stdin_read_all_handle(void);
void* rt_process_executable_handle(void);
void* rt_process_host_target_handle(void);
void rt_process_set_args(int argc, char** argv);

#endif /* ROLANG_STD_PROCESS_H */
