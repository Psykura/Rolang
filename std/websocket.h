#ifndef ROLANG_STD_WEBSOCKET_H
#define ROLANG_STD_WEBSOCKET_H

#include "../runtime/abi.h"
#include "string.h"

void* rt_ws_sha1(void* input);
void* rt_ws_frame(int32_t opcode, int32_t fin, void* payload, void* key);
void* rt_ws_mask(void* data, void* key);
void* rt_ws_close_payload(int32_t code, void* reason);

#endif /* ROLANG_STD_WEBSOCKET_H */
