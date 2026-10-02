#ifndef ROLANG_STD_TIME_H
#define ROLANG_STD_TIME_H

#include "../runtime/abi.h"

int64_t rt_time_monotonic_ns(void);
int64_t rt_time_unix_ns(void);
void rt_time_sleep_ns(int64_t nanoseconds);
int32_t rt_time_utc_offset(int64_t unix_seconds);

#endif /* ROLANG_STD_TIME_H */
