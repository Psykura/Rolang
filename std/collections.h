#ifndef ROLANG_STD_COLLECTIONS_H
#define ROLANG_STD_COLLECTIONS_H

#include <stddef.h>
#include <string.h>

/* memcpy with the common tiny sizes peeled into constant-size copies the
 * compiler lowers to single load/store pairs. Collection elements are almost
 * always 1/2/4/8/16 bytes (primitives, object pointers, StringVal pairs);
 * a variable-length memcpy is a libcall on every get/set. */
static inline void _rt_copy_small(void* dst, const void* src, size_t n) {
    switch (n) {
    case 1:  memcpy(dst, src, 1);  return;
    case 2:  memcpy(dst, src, 2);  return;
    case 4:  memcpy(dst, src, 4);  return;
    case 8:  memcpy(dst, src, 8);  return;
    case 16: memcpy(dst, src, 16); return;
    default: memcpy(dst, src, n);  return;
    }
}


#endif /* ROLANG_STD_COLLECTIONS_H */
