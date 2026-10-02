#include "../runtime/platform.h"
#include "time.h"

/* Clocks for std.time: a monotonic clock for measuring intervals and the
 * wall clock as nanoseconds since the Unix epoch. */

int64_t rt_time_monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000000000 + (int64_t)now.tv_nsec;
}

int64_t rt_time_unix_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return (int64_t)now.tv_sec * 1000000000 + (int64_t)now.tv_nsec;
}

/* Blocks the thread; an interrupted sleep resumes for the remaining time. */
void rt_time_sleep_ns(int64_t nanoseconds) {
    if (nanoseconds <= 0) return;
    struct timespec wanted = { (time_t)(nanoseconds / 1000000000), (long)(nanoseconds % 1000000000) };
    struct timespec left;
    while (nanosleep(&wanted, &left) != 0 && errno == EINTR) wanted = left;
}

/* Seconds east of UTC for the local time zone at the given instant. */
int32_t rt_time_utc_offset(int64_t unix_seconds) {
#if defined(__unix__) || defined(__APPLE__)
    time_t seconds = (time_t)unix_seconds;
    struct tm local;
    if (!localtime_r(&seconds, &local)) return 0;
    return (int32_t)local.tm_gmtoff;
#else
    (void)unix_seconds;
    return 0;
#endif
}
