#include "../runtime/platform.h"
#include "random.h"

/* 64 bits from the operating system's entropy source, for seeding. */
uint64_t rt_random_entropy(void) {
    uint64_t value = 0;
#if defined(__APPLE__)
    arc4random_buf(&value, sizeof(value));
#elif defined(__unix__)
    if (getentropy(&value, sizeof(value)) != 0) {
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        value = ((uint64_t)now.tv_sec << 30) ^ (uint64_t)now.tv_nsec ^ (uint64_t)(uintptr_t)&value;
    }
#endif
    return value;
}
