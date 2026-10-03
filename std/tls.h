#ifndef ROLANG_STD_TLS_H
#define ROLANG_STD_TLS_H

#include "../runtime/abi.h"
#include "string.h"
#include "../runtime/task.h"

void* rt_tls_context_new(int32_t server, int32_t verify, void* ca_file, void* certificate, void* key, void* alpn);
void rt_tls_context_free(void* context);
void* rt_tls_failure(void);
void* rt_tls_session_new(void* context, void* stream, void* host, int32_t server);
void rt_tls_session_free(void* session);
int32_t rt_tls_handshake(void* session);
void* rt_tls_read(void* session, int32_t limit, int32_t* status);
int32_t rt_tls_write(void* session, void* data, int32_t offset, int32_t* status);
int32_t rt_tls_shutdown(void* session);
void* rt_tls_session_error(void* session);
void* rt_tls_alpn(void* session);
void* rt_tls_version(void* session);
TaskHandle* rt_tls_wait_start(void* session, int32_t writable);

#endif /* ROLANG_STD_TLS_H */
