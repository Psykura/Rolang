#ifndef ROLANG_STD_REGEX_H
#define ROLANG_STD_REGEX_H

#include "../runtime/abi.h"
#include "string.h"
#include <ctype.h>

void* rt_regex_failure(void);
void* rt_regex_compile(void* pattern, int32_t flags);
void rt_regex_free(void* regex);
int32_t rt_regex_groups(void* regex);
int32_t rt_regex_group_index(void* regex, void* name);
void* rt_regex_group_name(void* regex, int32_t index);
int32_t rt_regex_search(void* regex, void* text, int64_t start);
int64_t rt_regex_capture_start(void* regex, int32_t index);
int64_t rt_regex_capture_end(void* regex, int32_t index);

#endif /* ROLANG_STD_REGEX_H */
