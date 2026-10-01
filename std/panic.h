#ifndef ROLANG_STD_PANIC_H
#define ROLANG_STD_PANIC_H

#include "../runtime/abi.h"
#include "string.h"


__attribute__((noreturn))
void rt_panic_msg(StringVal msg);
__attribute__((noreturn))
void rt_panic_msg_string(void* msg);

#endif /* ROLANG_STD_PANIC_H */
