#include "../runtime/platform.h"
#include "compress.h"
#include "../runtime/api.h"

/* gzip, zlib and raw deflate for std.compress, through the system's zlib,
 * loaded with dlopen on first use (it ships with macOS and practically every
 * Linux). Failures return NULL with the reason in rt_compress_failure. */

static RL_TLS char compress_failure[256];

static void compress_fail(const char* message) {
    snprintf(compress_failure, sizeof(compress_failure), "%s", message);
}

void* rt_compress_failure(void) {
    size_t size = strlen(compress_failure);
    char* copy = malloc(size + 1);
    if (!copy) rt_panic("compress allocation failed");
    memcpy(copy, compress_failure, size + 1);
    return rl_string_handle_from_value((StringVal){copy, (int64_t)size});
}

#if defined(__unix__) || defined(__APPLE__)
#include <dlfcn.h>
#include <pthread.h>

/* zlib's z_stream, whose layout is part of its stable ABI. */
typedef struct {
    const unsigned char* next_in; unsigned int avail_in; unsigned long total_in;
    unsigned char* next_out; unsigned int avail_out; unsigned long total_out;
    const char* msg; void* state;
    void* zalloc; void* zfree; void* opaque;
    int data_type; unsigned long adler; unsigned long reserved;
} ZStream;

enum { Z_OK = 0, Z_STREAM_END = 1, Z_NEED_DICT = 2, Z_BUF_ERROR = -5, Z_FINISH = 4, Z_NO_FLUSH = 0, Z_DEFLATED = 8 };

static struct {
    int state;
    int (*deflateInit2_)(ZStream*, int, int, int, int, int, const char*, int);
    int (*deflate)(ZStream*, int);
    int (*deflateEnd)(ZStream*);
    int (*inflateInit2_)(ZStream*, int, const char*, int);
    int (*inflate)(ZStream*, int);
    int (*inflateEnd)(ZStream*);
    unsigned long (*crc32)(unsigned long, const unsigned char*, unsigned int);
} zlib;

static pthread_mutex_t zlib_load_lock = PTHREAD_MUTEX_INITIALIZER;
static char zlib_load_message[256];
static int zlib_load_locked(void);

static int zlib_load(void) {
    int state = __atomic_load_n(&zlib.state, __ATOMIC_ACQUIRE);
    if (!state) {
        pthread_mutex_lock(&zlib_load_lock);
        if (!zlib.state) zlib_load_locked();
        state = zlib.state;
        pthread_mutex_unlock(&zlib_load_lock);
    }
    if (state < 0) compress_fail(zlib_load_message);
    return state > 0;
}

static int zlib_load_locked(void) {
    const char* candidates[] = {
#ifdef __APPLE__
        "/usr/lib/libz.1.dylib",
#else
        "libz.so.1", "libz.so",
#endif
    };
    void* library = NULL;
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]) && !library; i++) library = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (!library) { snprintf(zlib_load_message, sizeof(zlib_load_message), "%s", "compression needs zlib (libz), which was not found"); __atomic_store_n(&zlib.state, -1, __ATOMIC_RELEASE); return 0; }
#define ZLIB_SYMBOL(name) \
    if (!(*(void**)&zlib.name = dlsym(library, #name))) { snprintf(zlib_load_message, sizeof(zlib_load_message), "%s", "the zlib library lacks " #name); __atomic_store_n(&zlib.state, -1, __ATOMIC_RELEASE); return 0; }
    ZLIB_SYMBOL(deflateInit2_) ZLIB_SYMBOL(deflate) ZLIB_SYMBOL(deflateEnd)
    ZLIB_SYMBOL(inflateInit2_) ZLIB_SYMBOL(inflate) ZLIB_SYMBOL(inflateEnd) ZLIB_SYMBOL(crc32)
#undef ZLIB_SYMBOL
    __atomic_store_n(&zlib.state, 1, __ATOMIC_RELEASE);
    return 1;
}

/* Window bits per format: 0 gzip, 1 zlib, 2 raw deflate. */
static int zlib_window(int32_t format) {
    if (format == 0) return 15 + 16;
    if (format == 1) return 15;
    return -15;
}

/* Output in chunks that grow as needed, so no size is guessed up front. */
typedef struct { unsigned char* data; size_t used, capacity; } ZBuffer;

static int zbuffer_reserve(ZBuffer* buffer, size_t extra) {
    if (buffer->used + extra <= buffer->capacity) return 1;
    size_t next = buffer->capacity ? buffer->capacity : 4096;
    while (next < buffer->used + extra) next *= 2;
    unsigned char* grown = realloc(buffer->data, next);
    if (!grown) return 0;
    buffer->data = grown; buffer->capacity = next;
    return 1;
}

void* rt_compress(void* input, int32_t format, int32_t level) {
    if (!zlib_load()) return NULL;
    StringVal value = rt_string_obj_value(input);
    if (level < 0 || level > 9) { compress_fail("the compression level must be 0 to 9"); return NULL; }
    ZStream stream; memset(&stream, 0, sizeof(stream));
    if (zlib.deflateInit2_(&stream, level, Z_DEFLATED, zlib_window(format), 8, 0, "1.2.11", (int)sizeof(ZStream)) != Z_OK) {
        compress_fail("cannot start compression"); return NULL;
    }
    ZBuffer out = { NULL, 0, 0 };
    const unsigned char* next = (const unsigned char*)(value.data ? value.data : "");
    int64_t left = value.len;
    int status = Z_OK;
    while (status != Z_STREAM_END) {
        if (stream.avail_in == 0 && left > 0) {
            unsigned int chunk = left > (1 << 30) ? (1u << 30) : (unsigned int)left;
            stream.next_in = next; stream.avail_in = chunk; next += chunk; left -= chunk;
        }
        if (!zbuffer_reserve(&out, 65536)) { zlib.deflateEnd(&stream); free(out.data); rt_panic("compress allocation failed"); }
        stream.next_out = out.data + out.used; stream.avail_out = (unsigned int)(out.capacity - out.used);
        status = zlib.deflate(&stream, left > 0 ? Z_NO_FLUSH : Z_FINISH);
        out.used = out.capacity - stream.avail_out;
        if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) { zlib.deflateEnd(&stream); free(out.data); compress_fail("compression failed"); return NULL; }
    }
    zlib.deflateEnd(&stream);
    if (!zbuffer_reserve(&out, 1)) rt_panic("compress allocation failed");
    out.data[out.used] = 0;
    return rl_string_handle_from_value((StringVal){(char*)out.data, (int64_t)out.used});
}

/* Fails when the output would exceed `limit` bytes, which stops a small
 * input from expanding into gigabytes (a "zip bomb"). Concatenated gzip
 * members are decompressed one after another. */
void* rt_decompress(void* input, int32_t format, int64_t limit) {
    if (!zlib_load()) return NULL;
    StringVal value = rt_string_obj_value(input);
    if (value.len > UINT32_MAX) { compress_fail("input too large"); return NULL; }
    ZStream stream; memset(&stream, 0, sizeof(stream));
    if (zlib.inflateInit2_(&stream, zlib_window(format), "1.2.11", (int)sizeof(ZStream)) != Z_OK) { compress_fail("cannot start decompression"); return NULL; }
    stream.next_in = (const unsigned char*)(value.data ? value.data : "");
    stream.avail_in = (unsigned int)value.len;
    ZBuffer out = { NULL, 0, 0 };
    int status = Z_OK;
    while (1) {
        if (!zbuffer_reserve(&out, 65536)) { zlib.inflateEnd(&stream); free(out.data); rt_panic("compress allocation failed"); }
        /* Room for at most one byte past the limit, so going over is seen without writing more. */
        size_t room = out.capacity - out.used;
        if (limit >= 0 && (size_t)limit + 1 - out.used < room) room = (size_t)limit + 1 - out.used;
        if (room > UINT32_MAX) room = UINT32_MAX;
        stream.next_out = out.data + out.used; stream.avail_out = (unsigned int)room;
        status = zlib.inflate(&stream, Z_NO_FLUSH);
        out.used += room - stream.avail_out;
        if (limit >= 0 && (int64_t)out.used > limit) {
            zlib.inflateEnd(&stream); free(out.data);
            snprintf(compress_failure, sizeof(compress_failure), "decompressed data exceeds the %lld-byte limit", (long long)limit);
            return NULL;
        }
        if (status == Z_STREAM_END) {
            /* Another gzip member may follow. */
            if (format == 0 && stream.avail_in > 0) {
                const unsigned char* rest = stream.next_in; unsigned int rest_size = stream.avail_in;
                zlib.inflateEnd(&stream); memset(&stream, 0, sizeof(stream));
                if (zlib.inflateInit2_(&stream, zlib_window(format), "1.2.11", (int)sizeof(ZStream)) != Z_OK) { free(out.data); compress_fail("cannot continue decompression"); return NULL; }
                stream.next_in = rest; stream.avail_in = rest_size;
                continue;
            }
            break;
        }
        if (status == Z_BUF_ERROR && stream.avail_in == 0) { zlib.inflateEnd(&stream); free(out.data); compress_fail("the compressed data is truncated"); return NULL; }
        if (status != Z_OK && status != Z_BUF_ERROR) {
            snprintf(compress_failure, sizeof(compress_failure), "invalid compressed data%s%s", stream.msg ? ": " : "", stream.msg ? stream.msg : "");
            zlib.inflateEnd(&stream); free(out.data);
            return NULL;
        }
    }
    zlib.inflateEnd(&stream);
    if (!zbuffer_reserve(&out, 1)) rt_panic("compress allocation failed");
    out.data[out.used] = 0;
    return rl_string_handle_from_value((StringVal){(char*)out.data, (int64_t)out.used});
}

/* CRC-32 (as in gzip and zip); -1 when zlib is unavailable. */
int64_t rt_crc32(void* input) {
    if (!zlib_load()) return -1;
    StringVal value = rt_string_obj_value(input);
    unsigned long crc = 0;
    const unsigned char* data = (const unsigned char*)(value.data ? value.data : "");
    int64_t left = value.len;
    while (left > 0) {
        unsigned int chunk = left > (1 << 30) ? (1u << 30) : (unsigned int)left;
        crc = zlib.crc32(crc, data, chunk); data += chunk; left -= chunk;
    }
    return (int64_t)(crc & 0xFFFFFFFFUL);
}

#else

void* rt_compress(void* input, int32_t format, int32_t level) { (void)input; (void)format; (void)level; compress_fail("compression is not supported on this platform"); return NULL; }
void* rt_decompress(void* input, int32_t format, int64_t limit) { (void)input; (void)format; (void)limit; compress_fail("compression is not supported on this platform"); return NULL; }
int64_t rt_crc32(void* input) { (void)input; return -1; }

#endif
