#ifndef ROLANG_STD_IO_H
#define ROLANG_STD_IO_H

#include "../runtime/abi.h"
#include "string.h"


void rt_print_i64(int64_t value);
void rt_io_print_str(void* s_obj);
void rt_io_println_str(void* s);
void rt_io_print_i32(int32_t value);
void rt_io_println_i32(int32_t value);
void rt_io_eprintln_str(void* object);

#endif /* ROLANG_STD_IO_H */
