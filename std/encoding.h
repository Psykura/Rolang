#ifndef ROLANG_STD_ENCODING_H
#define ROLANG_STD_ENCODING_H

#include "../runtime/abi.h"
#include "string.h"

void* rt_hex_encode(void* string, int32_t upper);
void* rt_hex_decode(void* string);
void* rt_base64_encode(void* string, int32_t url, int32_t padding);
void* rt_base64_decode(void* string);

#endif /* ROLANG_STD_ENCODING_H */
