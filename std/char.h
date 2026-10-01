#ifndef ROLANG_STD_CHAR_H
#define ROLANG_STD_CHAR_H

#include "../runtime/abi.h"
#include "string.h"


int32_t rt_char_is_digit(int32_t ch);
int32_t rt_char_is_alpha(int32_t ch);
int32_t rt_char_is_alnum(int32_t ch);
int32_t rt_char_is_space(int32_t ch);

#endif /* ROLANG_STD_CHAR_H */
