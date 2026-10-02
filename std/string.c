#include "../runtime/platform.h"
#include "string.h"
#include "../runtime/api.h"
#include "vec.h"

/**
 * Destroy a string value, freeing only the heap data.
 *
 * StringVal is the value-type representation {data, len} used by
 * rt_str_concat, rt_int_to_string, and similar functions.  Only the
 * `data` pointer is heap-allocated; the struct itself lives on the
 * stack.  Call this when a String value is no longer needed.
 *
 * @param s String value whose data will be freed
 */
void rt_string_destroy(StringVal s) {
    if (s.data != NULL) {
        free(s.data);
    }
}

// String utilities for Rolang stdlib

int64_t rt_str_len(StringVal s) {
    return s.len;
}

int64_t rt_str_is_empty(StringVal s) {
    return (s.len == 0) ? 1 : 0;
}

int32_t rt_str_compare(StringVal a, StringVal b) {
    int64_t min_len = (a.len < b.len) ? a.len : b.len;
    if (min_len > 0 && a.data && b.data) {
        int cmp = memcmp(a.data, b.data, (size_t)min_len);
        if (cmp != 0) return (cmp < 0) ? -1 : 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

int32_t rt_str_contains(StringVal haystack, StringVal needle) {
    if (needle.len == 0) return 1;
    if (needle.len > haystack.len) return 0;
    if (!haystack.data || !needle.data) return 0;
    for (int64_t i = 0; i <= haystack.len - needle.len; i++) {
        if (memcmp(haystack.data + i, needle.data, (size_t)needle.len) == 0)
            return 1;
    }
    return 0;
}

int32_t rt_str_starts_with(StringVal s, StringVal prefix) {
    if (prefix.len > s.len) return 0;
    if (prefix.len == 0) return 1;
    if (!s.data || !prefix.data) return 0;
    return (memcmp(s.data, prefix.data, (size_t)prefix.len) == 0) ? 1 : 0;
}

int32_t rt_str_ends_with(StringVal s, StringVal suffix) {
    if (suffix.len > s.len) return 0;
    if (suffix.len == 0) return 1;
    if (!s.data || !suffix.data) return 0;
    return (memcmp(s.data + s.len - suffix.len, suffix.data, (size_t)suffix.len) == 0) ? 1 : 0;
}

// String construction helpers

StringVal rt_str_concat(StringVal a, StringVal b) {
    int64_t total_len = a.len + b.len;
    if (total_len == 0) return (StringVal){NULL, 0};
    char* buf = (char*)malloc((size_t)total_len + 1);
    if (!buf) return (StringVal){NULL, 0};
    if (a.data && a.len > 0) memcpy(buf, a.data, (size_t)a.len);
    if (b.data && b.len > 0) memcpy(buf + a.len, b.data, (size_t)b.len);
    buf[total_len] = '\0';
    return (StringVal){buf, total_len};
}

StringVal rt_int_to_string(int64_t value) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)value);
    if (len <= 0) return (StringVal){NULL, 0};
    char* data = (char*)malloc((size_t)len + 1);
    if (!data) return (StringVal){NULL, 0};
    memcpy(data, buf, (size_t)len + 1);
    return (StringVal){data, (int64_t)len};
}

StringVal rt_str_repeat(StringVal s, int32_t count) {
    if (count <= 0 || s.len == 0) return (StringVal){NULL, 0};
    /* Reject pathological inputs that would overflow int64 during the
     * length computation (`s.len * count`). Without this check a caller
     * supplying a large `s.len` and `count` could wrap to a small or
     * negative `total`, the malloc would succeed, and the memcpy loop
     * would write far past the allocated buffer — a classic heap
     * overflow. We also guard against the +1 NUL byte overflowing. */
    if (s.len > (INT64_MAX - 1) / (int64_t)count) {
        rt_panic("rt_str_repeat: result length overflows int64");
    }
    int64_t total = (int64_t)s.len * (int64_t)count;
    char* buf = (char*)malloc((size_t)total + 1);
    if (!buf) return (StringVal){NULL, 0};
    for (int32_t i = 0; i < count; i++) {
        memcpy(buf + (size_t)i * (size_t)s.len, s.data, (size_t)s.len);
    }
    buf[total] = '\0';
    return (StringVal){buf, total};
}

// String inspection helpers

int32_t rt_str_char_at(StringVal s, int32_t index) {
    if (index < 0 || index >= s.len) return -1;
    return (unsigned char)s.data[index];
}

int32_t rt_str_find_char(StringVal s, int32_t ch, int32_t start) {
    if (start < 0) start = 0;
    for (int64_t i = start; i < s.len; i++) {
        if ((unsigned char)s.data[i] == ch) return (int32_t)i;
    }
    return -1;
}

StringVal rt_str_substring(StringVal s, int32_t start, int32_t length) {
    if (start < 0) start = 0;
    if (start >= s.len || length <= 0) return (StringVal){NULL, 0};
    /* Promote to int64 so ``start + length`` cannot wrap around when both
     * are near INT32_MAX. The old int32 comparison silently took the
     * "fits" branch on overflow and memcpy then read far past the buffer. */
    int64_t end = (int64_t)start + (int64_t)length;
    int64_t cap = (end <= s.len) ? (int64_t)length : (s.len - (int64_t)start);
    if (cap <= 0) return (StringVal){NULL, 0};
    int32_t actual_len = (cap > INT32_MAX) ? INT32_MAX : (int32_t)cap;
    char* buf = (char*)malloc((size_t)actual_len + 1);
    if (!buf) return (StringVal){NULL, 0};
    memcpy(buf, s.data + start, (size_t)actual_len);
    buf[actual_len] = 0;
    return (StringVal){buf, actual_len};
}

int32_t _is_whitespace(char c) {
    return (c == ' ' || c == '\t' || c == '\n' || c == '\r');
}

StringVal rt_str_trim(StringVal s) {
    if (s.len == 0 || !s.data) return (StringVal){NULL, 0};
    int64_t start = 0;
    int64_t end = s.len - 1;
    while (start < s.len && _is_whitespace(s.data[start])) start++;
    while (end >= start && _is_whitespace(s.data[end])) end--;
    if (start > end) return (StringVal){NULL, 0};
    int64_t new_len = end - start + 1;
    char* buf = (char*)malloc((size_t)new_len + 1);
    if (!buf) return (StringVal){NULL, 0};
    memcpy(buf, s.data + start, (size_t)new_len);
    buf[new_len] = 0;
    return (StringVal){buf, new_len};
}

StringVal rt_str_replace(StringVal s, StringVal old, StringVal new_val) {
    if (s.len == 0 || old.len == 0 || old.len > s.len || !s.data || !old.data) {
        /* Return a fresh copy of s so the caller can safely destroy both
         * the input and the return value without double-freeing .data */
        if (s.len == 0 || !s.data) return (StringVal){NULL, 0};
        char* copy = (char*)malloc((size_t)s.len + 1);
        if (!copy) return (StringVal){NULL, 0};
        memcpy(copy, s.data, (size_t)s.len);
        copy[s.len] = '\0';
        return (StringVal){copy, s.len};
    }
    // Count occurrences
    int64_t count = 0;
    for (int64_t i = 0; i <= s.len - old.len; i++) {
        if (memcmp(s.data + i, old.data, (size_t)old.len) == 0) {
            count++;
            i += old.len - 1;
        }
    }
    if (count == 0) {
        /* No replacements — return a fresh copy of s */
        char* copy = (char*)malloc((size_t)s.len + 1);
        if (!copy) return (StringVal){NULL, 0};
        memcpy(copy, s.data, (size_t)s.len);
        copy[s.len] = '\0';
        return (StringVal){copy, s.len};
    }
    int64_t new_len = s.len + count * (new_val.len - old.len);
    char* buf = (char*)malloc((size_t)new_len + 1);
    if (!buf) {
        /* Could not allocate result — return a copy of s instead */
        char* copy = (char*)malloc((size_t)s.len + 1);
        if (!copy) return (StringVal){NULL, 0};
        memcpy(copy, s.data, (size_t)s.len);
        copy[s.len] = '\0';
        return (StringVal){copy, s.len};
    }

    char* dst = buf;
    int64_t i = 0;
    while (i < s.len) {
        if (i <= s.len - old.len && memcmp(s.data + i, old.data, (size_t)old.len) == 0) {
            if (new_val.data && new_val.len > 0) {
                memcpy(dst, new_val.data, (size_t)new_val.len);
                dst += new_val.len;
            }
            i += old.len;
        } else {
            *dst++ = s.data[i++];
        }
    }
    *dst = 0;
    return (StringVal){buf, new_len};
}

/**
 * In-place string replacement: modifies s.data, returns updated fat pointer.
 *
 * Unlike rt_str_replace which always allocates a new buffer, this function
 * reuses the original buffer via realloc when the size changes, and returns
 * the (possibly updated) StringVal.  When old_len == new_val_len, replacement
 * is done in-place without any allocation.
 *
 * On allocation failure the original string is returned unchanged.
 */
StringVal rt_str_replace_self(StringVal s, StringVal old, StringVal new_val) {
    if (s.len == 0 || old.len == 0 || old.len > s.len || !s.data || !old.data) {
        return s;
    }

    /* Count occurrences */
    int64_t count = 0;
    int64_t old_len = old.len;
    for (int64_t i = 0; i <= s.len - old_len; i++) {
        if (memcmp(s.data + i, old.data, (size_t)old_len) == 0) {
            count++;
            i += old_len - 1;
        }
    }

    if (count == 0) {
        return s;  /* No matches — return self unchanged */
    }

    int64_t new_len = s.len + count * (new_val.len - old_len);

    if (old_len == new_val.len) {
        /* Same-size replacement: pure in-place, no allocation */
        int64_t i = 0;
        while (i < s.len) {
            if (i <= s.len - old_len
                && memcmp(s.data + i, old.data, (size_t)old_len) == 0) {
                if (new_val.data && new_val.len > 0) {
                    memcpy(s.data + i, new_val.data, (size_t)new_val.len);
                }
                i += old_len;
            } else {
                i++;
            }
        }
        s.len = new_len;
        return s;
    }

    /* Size changes — build result in temp buffer, then realloc original
     * and copy back.  This avoids the complexity of right-to-left in-place
     * replacement when the result is larger. */
    char* buf = (char*)malloc((size_t)new_len + 1);
    if (!buf) {
        return s;  /* Allocation failed, return unchanged */
    }

    char* dst = buf;
    int64_t i = 0;
    while (i < s.len) {
        if (i <= s.len - old_len
            && memcmp(s.data + i, old.data, (size_t)old_len) == 0) {
            if (new_val.data && new_val.len > 0) {
                memcpy(dst, new_val.data, (size_t)new_val.len);
                dst += new_val.len;
            }
            i += old_len;
        } else {
            *dst++ = s.data[i++];
        }
    }
    *dst = '\0';

    /* Realloc original to the new size and copy result back.  If realloc
     * fails, the original allocation is untouched — return it unchanged. */
    char* new_data = (char*)realloc(s.data, (size_t)new_len + 1);
    if (new_data) {
        s.data = new_data;
        memcpy(s.data, buf, (size_t)new_len + 1);
    }
    free(buf);

    s.len = new_len;
    return s;
}

/* ============================================================================
 * String parsing
 * ============================================================================ */

int64_t rt_str_to_i64(StringVal s) {
    if (s.len == 0 || !s.data) return 0;
    int64_t sign = 1;
    int64_t i = 0;
    if (s.data[0] == '-') { sign = -1; i = 1; }
    else if (s.data[0] == '+') { i = 1; }
    int64_t result = 0;
    for (; i < s.len; i++) {
        char c = s.data[i];
        if (c < '0' || c > '9') break;
        result = result * 10 + (c - '0');
    }
    return result * sign;
}

int32_t rt_str_to_i32(StringVal s) {
    return (int32_t)rt_str_to_i64(s);
}

/* Split `s` on every occurrence of `sep`. Returns a gvec of StringVal,
 * each entry freshly heap-allocated.  Empty `sep` returns NULL.
 *
 * Used by std/string.rl `String.split` extension method.
 */
void* rt_str_split(StringVal s, StringVal sep) {
    if (sep.len == 0 || !sep.data) return NULL;
    void* vec = rt_gvec_new(8, (int32_t)sizeof(StringVal), 0);
    if (!vec) return NULL;
    if (s.len == 0 || !s.data) return vec;
    int64_t start = 0;
    int64_t i = 0;
    while (i <= s.len - sep.len) {
        if (memcmp(s.data + i, sep.data, (size_t)sep.len) == 0) {
            int64_t piece_len = i - start;
            char* buf = (char*)malloc((size_t)piece_len + 1);
            if (buf) {
                if (piece_len > 0) memcpy(buf, s.data + start, (size_t)piece_len);
                buf[piece_len] = '\0';
                StringVal entry = {buf, piece_len};
                vec = rt_gvec_push(vec, &entry);
            }
            i += sep.len;
            start = i;
        } else {
            i++;
        }
    }
    /* Tail piece (everything from `start` to end, even if empty). */
    int64_t tail_len = s.len - start;
    char* buf = (char*)malloc((size_t)tail_len + 1);
    if (buf) {
        if (tail_len > 0) memcpy(buf, s.data + start, (size_t)tail_len);
        buf[tail_len] = '\0';
        StringVal entry = {buf, tail_len};
        vec = rt_gvec_push(vec, &entry);
    }
    return vec;
}

/* Split on '\n'. Trailing '\r' on each line (Windows line endings) is
 * stripped. The final empty line at EOF is dropped, matching what
 * `for line in file.read().lines()` should do.
 */
void* rt_str_lines(StringVal s) {
    void* vec = rt_gvec_new(8, (int32_t)sizeof(StringVal), 0);
    if (!vec) return NULL;
    if (s.len == 0 || !s.data) return vec;
    int64_t start = 0;
    for (int64_t i = 0; i < s.len; i++) {
        if (s.data[i] == '\n') {
            int64_t end = i;
            if (end > start && s.data[end - 1] == '\r') end--;
            int64_t piece_len = end - start;
            char* buf = (char*)malloc((size_t)piece_len + 1);
            if (buf) {
                if (piece_len > 0) memcpy(buf, s.data + start, (size_t)piece_len);
                buf[piece_len] = '\0';
                StringVal entry = {buf, piece_len};
                vec = rt_gvec_push(vec, &entry);
            }
            start = i + 1;
        }
    }
    if (start < s.len) {
        int64_t piece_len = s.len - start;
        char* buf = (char*)malloc((size_t)piece_len + 1);
        if (buf) {
            memcpy(buf, s.data + start, (size_t)piece_len);
            buf[piece_len] = '\0';
            StringVal entry = {buf, piece_len};
            vec = rt_gvec_push(vec, &entry);
        }
    }
    return vec;
}

/* f64 / Bool parsing helpers. */
double rt_str_to_f64(StringVal s) {
    if (s.len == 0 || !s.data) return 0.0;
    /* Defensive: ensure null-termination by copying into a local buffer. */
    char stackbuf[64];
    char* c = stackbuf;
    if ((size_t)s.len + 1 > sizeof(stackbuf)) {
        c = (char*)malloc((size_t)s.len + 1);
        if (!c) return 0.0;
    }
    memcpy(c, s.data, (size_t)s.len);
    c[s.len] = '\0';
    double v = strtod(c, NULL);
    if (c != stackbuf) free(c);
    return v;
}

static StringVal rl_string_from_buffer(const char* buf, int n) {
    StringVal sv = {NULL, 0};
    if (n < 0) return sv;
    char* data = (char*)malloc((size_t)n + 1);
    if (!data) return sv;
    memcpy(data, buf, (size_t)n + 1);
    sv.data = data;
    sv.len = (int64_t)n;
    return sv;
}

/* Convert f64 -> StringVal with the fewest significant digits that read back
 * as the same value: 0.1 + 0.2 prints 0.30000000000000004. Like Python's repr,
 * exponents from -4 to 15 print positionally (1000, 0.001), others as 1e+21.
 * Caller owns the data. */
StringVal rt_f64_to_string(double val) {
    char buf[400];
    int n = 0;
    if (val != val) return rl_string_from_buffer("nan", 3);
    if (val - val != 0) return val > 0 ? rl_string_from_buffer("inf", 3) : rl_string_from_buffer("-inf", 4);
    int digits = 17;
    for (int precision = 1; precision <= 17; precision++) {
        snprintf(buf, sizeof(buf), "%.*e", precision - 1, val);
        if (strtod(buf, NULL) == val) { digits = precision; break; }
    }
    snprintf(buf, sizeof(buf), "%.*e", digits - 1, val);
    int exponent = atoi(strchr(buf, 'e') + 1);
    if (val != 0 && (exponent < -4 || exponent >= 16)) {
        n = snprintf(buf, sizeof(buf), "%.*g", digits, val);
    } else {
        int decimals = digits - 1 - exponent;
        if (decimals < 0) decimals = 0;
        n = snprintf(buf, sizeof(buf), "%.*f", decimals, val);
    }
    return rl_string_from_buffer(buf, n);
}

/* Fixed ('f'), exponent ('e') or general ('g') notation with `precision` digits. */
void* rt_f64_format_handle(double value, int32_t precision, int32_t style) {
    char buf[400];
    if (precision < 0) precision = 6;
    if (precision > 100) precision = 100;
    const char* format = "%.*f";
    if (style == 'e') format = "%.*e";
    else if (style == 'g') format = "%.*g";
    int n = snprintf(buf, sizeof(buf), format, (int)precision, value);
    if (n >= (int)sizeof(buf)) n = (int)sizeof(buf) - 1;
    return rl_string_handle_from_value(rl_string_from_buffer(buf, n));
}

/* -------------------------------------------------------------------------
 * Heap String object bridge.
 * ------------------------------------------------------------------------- */

void* rl_string_handle_from_value(StringVal s) {
    StringVal* handle = (StringVal*)malloc(sizeof(StringVal));
    if (handle == NULL) {
        rt_string_destroy(s);
        return NULL;
    }
    *handle = s;
    return handle;
}

void* rt_string_from_rodata(const char* data, int64_t len) {
    if (len <= 0) {
        return rl_string_handle_from_value((StringVal){NULL, 0});
    }
    char* copy = (char*)malloc((size_t)len + 1);
    if (copy == NULL) {
        return rl_string_handle_from_value((StringVal){NULL, 0});
    }
    if (data != NULL) memcpy(copy, data, (size_t)len);
    copy[len] = '\0';
    return rl_string_handle_from_value((StringVal){copy, len});
}

void rt_string_free_data(void* data) {
    if (data != NULL) free(data);
}

void rt_string_free_handle(void* handle) {
    if (handle == NULL) return;
    StringVal s = *(StringVal*)handle;
    rt_string_destroy(s);
    free(handle);
}

char* rt_string_handle_data(void* handle) {
    if (handle == NULL) return NULL;
    return ((StringVal*)handle)->data;
}

int64_t rt_string_handle_len(void* handle) {
    if (handle == NULL) return 0;
    return ((StringVal*)handle)->len;
}

void rt_string_free_handle_only(void* handle) {
    free(handle);
}

void rt_string_release(void* s) {
    if (s != NULL) rt_obj_release(s);
}

int64_t rt_string_len(void* s) { return rt_str_len(rt_string_obj_value(s)); }
int64_t rt_string_is_empty(void* s) { return rt_str_is_empty(rt_string_obj_value(s)); }
int32_t rt_string_compare(void* a, void* b) { return rt_str_compare(rt_string_obj_value(a), rt_string_obj_value(b)); }
int32_t rt_string_contains(void* h, void* n) { return rt_str_contains(rt_string_obj_value(h), rt_string_obj_value(n)); }
int32_t rt_string_starts_with(void* s, void* p) { return rt_str_starts_with(rt_string_obj_value(s), rt_string_obj_value(p)); }
int32_t rt_string_ends_with(void* s, void* suffix) { return rt_str_ends_with(rt_string_obj_value(s), rt_string_obj_value(suffix)); }
void* rt_string_concat_handle(void* a, void* b) { return rl_string_handle_from_value(rt_str_concat(rt_string_obj_value(a), rt_string_obj_value(b))); }
void* rt_int_to_string_handle(int64_t value) { return rl_string_handle_from_value(rt_int_to_string(value)); }
void* rt_u64_to_string_handle(uint64_t value) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%llu", (unsigned long long)value);
    char* data = (char*)malloc((size_t)len + 1);
    if (!data) rt_panic("out of memory formatting integer");
    memcpy(data, buf, (size_t)len + 1);
    return rl_string_handle_from_value((StringVal){data, (int64_t)len});
}
void* rt_f64_to_string_handle(double value) { return rl_string_handle_from_value(rt_f64_to_string(value)); }
void* rt_string_repeat_handle(void* s, int32_t count) { return rl_string_handle_from_value(rt_str_repeat(rt_string_obj_value(s), count)); }
int32_t rt_string_char_at(void* s, int32_t index) { return rt_str_char_at(rt_string_obj_value(s), index); }
int32_t rt_string_find_char(void* s, int32_t ch, int32_t start) { return rt_str_find_char(rt_string_obj_value(s), ch, start); }
void* rt_string_substring_handle(void* s, int32_t start, int32_t len) { return rl_string_handle_from_value(rt_str_substring(rt_string_obj_value(s), start, len)); }
void* rt_string_trim_handle(void* s) { return rl_string_handle_from_value(rt_str_trim(rt_string_obj_value(s))); }
void* rt_string_replace_handle(void* s, void* old, void* new_val) {
    return rl_string_handle_from_value(rt_str_replace(
        rt_string_obj_value(s),
        rt_string_obj_value(old),
        rt_string_obj_value(new_val)
    ));
}
int64_t rt_string_to_i64(void* s) { return rt_str_to_i64(rt_string_obj_value(s)); }
int32_t rt_string_to_i32(void* s) { return rt_str_to_i32(rt_string_obj_value(s)); }
double rt_string_to_f64(void* s) { return rt_str_to_f64(rt_string_obj_value(s)); }
