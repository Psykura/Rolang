#ifndef ROLANG_STD_COMPRESS_H
#define ROLANG_STD_COMPRESS_H

#include "../runtime/abi.h"
#include "string.h"

void* rt_compress_failure(void);
void* rt_compress(void* input, int32_t format, int32_t level);
void* rt_decompress(void* input, int32_t format, int64_t limit);
int64_t rt_crc32(void* input);

#endif /* ROLANG_STD_COMPRESS_H */
