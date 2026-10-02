#ifndef ROLANG_STD_UNICODE_H
#define ROLANG_STD_UNICODE_H

#include "../runtime/abi.h"
#include "string.h"

int32_t rt_string_scalar_at(void* s, int32_t offset);
int32_t rt_string_scalar_width(void* s, int32_t offset);
int32_t rt_string_grapheme_end(void* s, int32_t offset);
int32_t rt_string_is_valid_utf8(void* s);
void* rt_string_from_scalar_handle(int32_t scalar);

#endif /* ROLANG_STD_UNICODE_H */
