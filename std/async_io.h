#ifndef ROLANG_STD_ASYNC_IO_H
#define ROLANG_STD_ASYNC_IO_H

#include "../runtime/abi.h"
#include "string.h"
#include "../runtime/task.h"


ROLANG_INTERNAL void rl_stream_release(AsyncStream* stream);
ROLANG_INTERNAL void rl_async_ready(TaskHandle* task);
ROLANG_INTERNAL void rl_resolve_release(TaskHandle* task);
TaskHandle* rt_net_resolve_start(void* host);
void* rt_net_resolve_result(TaskHandle* task, int32_t* error);
ROLANG_INTERNAL AsyncStream* rl_stream_adopt(int fd);
TaskHandle* rt_async_connect_start(void* address, int32_t port);
int32_t rt_async_listener_bind(void* address, int32_t port, int32_t backlog, void** out);
int32_t rt_async_listener_port(void* ptr);
TaskHandle* rt_async_accept_start(void* ptr);
void* rt_async_take_stream(TaskHandle* task);
void* rt_async_stream_adopt(int32_t fd);
void* rt_async_stream_pair(void** other);
void rt_async_stream_close(void* stream);
int32_t rt_async_stream_shutdown(void* ptr);
TaskHandle* rt_async_read_start(void* ptr, int32_t limit);
TaskHandle* rt_async_write_start(void* ptr, void* string);
void* rt_async_read_data(TaskHandle* task);
int32_t rt_udp_bind(void* address, int32_t port, void** out);
TaskHandle* rt_udp_send_start(void* socket, void* data, void* address, int32_t port);
TaskHandle* rt_udp_receive_start(void* socket, int32_t limit);
void* rt_udp_received_data(TaskHandle* task);
void* rt_udp_received_address(TaskHandle* task, int32_t* port);
int32_t rt_socket_port(void* socket);
void* rt_os_error_message(int32_t code);
int32_t rt_errno_host_unreachable(void);
ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);

#endif /* ROLANG_STD_ASYNC_IO_H */
