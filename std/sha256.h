#ifndef ROLANG_STD_SHA256_H
#define ROLANG_STD_SHA256_H

#include "../runtime/abi.h"
#include "string.h"


ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);
void* rt_sha256_string_handle(void* object);
void* rt_sha256_file_handle(void* object);

#endif /* ROLANG_STD_SHA256_H */
