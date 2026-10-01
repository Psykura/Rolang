#ifndef ROLANG_STD_STRING_BUILDER_H
#define ROLANG_STD_STRING_BUILDER_H

#include "../runtime/abi.h"
#include "string.h"


ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);
void* rt_string_builder_new(void);
void rt_string_builder_append(void* ptr, void* text);
void rt_string_builder_byte(void* ptr, uint8_t value);
int64_t rt_string_builder_len(void* ptr);
void rt_string_builder_clear(void* ptr);
void* rt_string_builder_text(void* ptr);
void rt_string_builder_free(void* ptr);

#endif /* ROLANG_STD_STRING_BUILDER_H */
