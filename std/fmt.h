#ifndef ROLANG_STD_FMT_H
#define ROLANG_STD_FMT_H

#include "../runtime/abi.h"
#include "string.h"

typedef union {
    int64_t   i;
    double    f;
    int32_t   b;
    StringVal s;
} FmtArg;

void* rt_format_int(const char* fmt, int32_t val);
void* rt_format_i64(const char* fmt, int64_t val);
void* rt_format_str(const char* fmt, const char* val);
StringVal rt_format_int_s(StringVal fmt, int32_t val);
StringVal rt_format_i64_s(StringVal fmt, int64_t val);
StringVal rt_format_str_s(StringVal fmt, StringVal val);
StringVal rt_format_f64_s(StringVal fmt, double val);
StringVal rt_format_bool_s(StringVal fmt, int32_t val);
void* rt_format_int_handle(void* fmt, int32_t val);
void* rt_format_i64_handle(void* fmt, int64_t val);
void* rt_format_f64_handle(void* fmt, double val);
void* rt_format_bool_handle(void* fmt, int32_t val);
void* rt_format_str_handle(void* fmt, void* val);
StringVal rt_fmt_args(StringVal fmt, int32_t nargs, const int32_t* kinds, const FmtArg* argv);

#endif /* ROLANG_STD_FMT_H */
