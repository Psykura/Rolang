#include "../runtime/platform.h"
#include "fs.h"
#include "../runtime/api.h"
#include "path.h"

/* ============================================================================
 * File I/O
 * ============================================================================ */

#include <sys/stat.h>

void* rt_file_open(const char* path, const char* mode) {
    if (!path || !mode) return NULL;
    return (void*)fopen(path, mode);
}

void rt_file_close(void* file) {
    if (file) fclose((FILE*)file);
}

int32_t rt_file_read(void* file, void* buf, int32_t size) {
    if (!file || !buf || size <= 0) return 0;
    size_t n = fread(buf, 1, (size_t)size, (FILE*)file);
    return (int32_t)n;
}

int32_t rt_file_write(void* file, const void* buf, int32_t size) {
    if (!file || !buf || size <= 0) return 0;
    size_t n = fwrite(buf, 1, (size_t)size, (FILE*)file);
    return (int32_t)n;
}

int32_t rt_file_seek(void* file, int64_t offset, int32_t whence) {
    if (!file) return -1;
    return fseek((FILE*)file, (long)offset, (int)whence);
}

int64_t rt_file_tell(void* file) {
    if (!file) return -1;
    return (int64_t)ftell((FILE*)file);
}

int32_t rt_file_flush(void* file) {
    if (!file) return -1;
    return fflush((FILE*)file);
}

int32_t rt_file_eof(void* file) {
    if (!file) return 1;
    return feof((FILE*)file);
}

void* rt_file_read_all(void* file) {
    if (!file) return NULL;
    FILE* f = (FILE*)file;
    long pos = ftell(f);
    if (pos < 0) return NULL;
    fseek(f, 0, SEEK_END);
    long end = ftell(f);
    fseek(f, pos, SEEK_SET);
    if (end < 0 || end < pos) return NULL;
    /* `end` is the absolute end-of-file offset; we need the number of
     * remaining bytes from `pos`. */
    long remaining = end - pos;
    char* buf = (char*)malloc((size_t)remaining + 1);
    if (!buf) return NULL;
    long n = (long)fread(buf, 1, (size_t)remaining, f);
    if (n < 0) n = 0;
    buf[n] = '\0';
    return (void*)buf;
}

/* Keep byte counts separate from C terminators: file contents can contain NUL.
 * This also supports non-seekable streams and reads from the current position. */
static StringVal rt_file_read_text(void* file, int line) {
    StringVal out = {NULL, 0};
    if (!file) return out;
    size_t capacity = 4096, length = 0;
    char* data = malloc(capacity);
    if (!data) return out;
    for (;;) {
        if (length == capacity - 1) {
            if (capacity > SIZE_MAX / 2 || capacity > INT64_MAX / 2) {
                free(data); return out;
            }
            size_t next_capacity = capacity * 2;
            char* next = realloc(data, next_capacity);
            if (!next) { free(data); return out; }
            data = next; capacity = next_capacity;
        }
        if (line) {
            int c = fgetc((FILE*)file);
            if (c == EOF) break;
            data[length++] = (char)c;
            if (c == '\n') break;
        } else {
            size_t n = fread(data + length, 1, capacity - length - 1, (FILE*)file);
            length += n;
            if (!n) break;
        }
    }
    data[length] = '\0'; out.data = data; out.len = (int64_t)length;
    return out;
}

StringVal rt_file_read_all_s(void* file) {
    return rt_file_read_text(file, 0);
}

void* rt_file_read_line(void* file) {
    if (!file) return NULL;
    FILE* f = (FILE*)file;
    size_t cap = 128;
    char* buf = (char*)malloc(cap);
    if (!buf) return NULL;
    size_t pos = 0;
    while (1) {
        int c = fgetc(f);
        if (c == EOF) {
            if (pos == 0) { free(buf); return NULL; }
            break;
        }
        buf[pos++] = (char)c;
        if (pos >= cap) {
            cap *= 2;
            char* new_buf = (char*)realloc(buf, cap);
            if (!new_buf) { free(buf); return NULL; }
            buf = new_buf;
        }
        if (c == '\n') break;
    }
    buf[pos] = '\0';
    return (void*)buf;
}

StringVal rt_file_read_line_s(void* file) {
    return rt_file_read_text(file, 1);
}

int32_t rt_file_write_str(void* file, const void* str) {
    if (!file || !str) return 0;
    size_t len = strlen((const char*)str);
    return rt_file_write(file, str, (int32_t)len);
}

int64_t rt_file_get_size(const char* path) {
    if (!path) return 0;
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return (int64_t)st.st_size;
}

// String-based wrappers for Rolang StringVal (fat pointer { data, len })
void* rt_file_open_s(StringVal path, StringVal mode) {
    return rt_file_open(path.data, mode.data);
}
int32_t rt_file_write_s(void* file, StringVal s) {
    if (s.len < 0 || s.len > INT32_MAX) return 0;
    return rt_file_write(file, s.data, (int32_t)s.len);
}
int64_t rt_file_get_size_s(StringVal path) {
    return rt_file_get_size(path.data);
}

void* rt_file_open_string(void* path, void* mode) {
    StringVal p = rt_string_obj_value(path);
    StringVal m = rt_string_obj_value(mode);
    return rt_file_open(p.data, m.data);
}

/* Open a file from a String path object using an integer mode:
 *   0 = read ("rb"), 1 = write/truncate ("wb"), 2 = append ("ab").
 * Binary modes are used so rt_file_read/rt_file_write byte counts are exact
 * on every platform. Returns a FILE* (as void*) or NULL on failure. */
void* rt_file_open_handle(void* path, int32_t mode) {
    StringVal p = rt_string_obj_value(path);
    if (p.data == NULL || p.len <= 0 || memchr(p.data, 0, (size_t)p.len)) return NULL;
    const char* m;
    switch (mode) {
        case 1:  m = "wb"; break;
        case 2:  m = "ab"; break;
        case 0:
        default: m = "rb"; break;
    }
    return rt_file_open(p.data, m);
}

int32_t rt_file_write_string(void* file, void* s_obj) {
    StringVal s = rt_string_obj_value(s_obj);
    return rt_file_write(file, s.data, (int32_t)s.len);
}

int64_t rt_file_get_size_string(void* path) {
    StringVal p = rt_string_obj_value(path);
    return rt_file_get_size(p.data);
}

void* rt_file_read_all_handle(void* file) {
    return rl_string_handle_from_value(rt_file_read_all_s(file));
}

void* rt_file_read_line_handle(void* file) {
    return rl_string_handle_from_value(rt_file_read_line_s(file));
}

/* Filesystem primitives used by native tools. All path arguments reject NUL,
 * and replacement uses a private temporary sibling followed by rename. */

int32_t rt_path_mkdirs(void* object) {
    const char* path = rt_checked_path(object);
    if (!path) return -1;
    char* copy = strdup(path);
    if (!copy) return -1;
    int rc = 0;
    for (char* p = copy + 1;; p++) {
        if (*p && *p != '/') continue;
        char saved = *p; *p = 0;
        if (mkdir(copy, 0755) != 0) {
            struct stat st;
            if (errno != EEXIST || stat(copy, &st) != 0 || !S_ISDIR(st.st_mode)) rc = -1;
        }
        *p = saved;
        if (!saved || rc) break;
    }
    free(copy); return rc;
}

void* rt_temp_dir_handle(void* object) {
    const char* pattern = rt_checked_path(object);
    if (!pattern) return NULL;
    char* copy = strdup(pattern);
    if (!copy) return NULL;
    if (!mkdtemp(copy)) { free(copy); return NULL; }
    return rl_string_handle_from_value((StringVal){copy, (int64_t)strlen(copy)});
}

int32_t rt_path_remove(void* object) {
    const char* path = rt_checked_path(object);
    if (!path) return -1;
    if (unlink(path) == 0) return 0;
    return rmdir(path);
}

int32_t rt_file_move(void* from, void* to) {
    const char* a = rt_checked_path(from); const char* b = rt_checked_path(to);
    return a && b ? rename(a, b) : -1;
}

int32_t rt_file_mode(void* object) {
    const char* path = rt_checked_path(object); struct stat st;
    return path && stat(path, &st) == 0 && S_ISREG(st.st_mode) ? (int32_t)(st.st_mode & 0777) : -1;
}
int64_t rt_file_size_checked(void* object) {
    const char* path = rt_checked_path(object); struct stat st;
    return path && stat(path, &st) == 0 && S_ISREG(st.st_mode) ? (int64_t)st.st_size : -1;
}

void* rt_file_read_checked_handle(void* object, int64_t limit) {
    const char* path = rt_checked_path(object); struct stat st;
    if (!path || limit < 0 || stat(path, &st) || !S_ISREG(st.st_mode) || st.st_size > limit) return NULL;
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    /* Read at most limit+1 bytes even if the file grows after stat. */
    size_t capacity = (size_t)st.st_size + 1, length = 0;
    char* data = malloc(capacity);
    int ok = data != NULL;
    while (ok) {
        if (length == capacity) {
            if ((int64_t)length > limit) { ok = 0; break; }
            size_t next = capacity < 4096 ? 4096 : capacity * 2;
            if (next > (uint64_t)limit + 1) next = (size_t)limit + 1;
            if (next <= capacity) { ok = 0; break; }
            char* grown = realloc(data, next);
            if (!grown) { ok = 0; break; }
            data = grown; capacity = next;
        }
        size_t n = fread(data + length, 1, capacity - length, f); length += n;
        if (!n) { if (ferror(f)) ok = 0; break; }
    }
    if (fclose(f) || (int64_t)length > limit) ok = 0;
    if (!ok) { free(data); return NULL; }
    char* terminated = realloc(data, length + 1);
    if (!terminated) { free(data); return NULL; }
    terminated[length] = 0;
    return rl_string_handle_from_value((StringVal){terminated, (int64_t)length});
}

static int rt_atomic_file(void* to, void* contents, const char* from, int32_t mode) {
    const char* path = rt_checked_path(to);
    if (!path || mode < -1 || mode > 0777) return -1;
    size_t n = strlen(path); char* temporary = malloc(n + 16);
    if (!temporary) return -1;
    memcpy(temporary, path, n); strcpy(temporary + n, ".tmp.XXXXXX");
    int fd = mkstemp(temporary); int ok = fd >= 0;
    FILE* output = ok ? fdopen(fd, "wb") : NULL;
    if (!output && fd >= 0) { close(fd); ok = 0; }
    if (ok && from) {
        FILE* input = fopen(from, "rb"); struct stat st;
        if (!input || fstat(fileno(input), &st) || !S_ISREG(st.st_mode)) ok = 0;
        else {
            if (mode < 0) mode = (int32_t)(st.st_mode & 0777);
            unsigned char buffer[65536]; size_t read;
            while ((read = fread(buffer, 1, sizeof(buffer), input)) > 0) {
                if (fwrite(buffer, 1, read, output) != read) { ok = 0; break; }
            }
            if (ferror(input)) ok = 0;
        }
        if (input && fclose(input)) ok = 0;
    } else if (ok) {
        StringVal text = rt_string_obj_value(contents);
        if (text.len < 0 || (text.len && (!text.data || fwrite(text.data, 1, (size_t)text.len, output) != (size_t)text.len))) ok = 0;
    }
    if (output) {
        if (fflush(output) || (mode >= 0 && fchmod(fd, (mode_t)mode)) || fsync(fd)) ok = 0;
        if (fclose(output)) ok = 0;
    }
    if (ok && rename(temporary, path)) ok = 0;
    if (!ok) unlink(temporary);
    free(temporary); return ok ? 0 : -1;
}

int32_t rt_file_write_atomic(void* path, void* text, int32_t mode) {
    return rt_atomic_file(path, text, NULL, mode);
}
int32_t rt_file_copy_atomic(void* from, void* to, int32_t mode) {
    const char* source = rt_checked_path(from);
    return source ? rt_atomic_file(to, NULL, source, mode) : -1;
}
