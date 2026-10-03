#ifndef ROLANG_STD_STRING_H
#define ROLANG_STD_STRING_H

#include "../runtime/abi.h"

/* ============================================================================
 * String Operations
 *
 * Source-level String is a managed object with an inline data/length/hash
 * payload. C value bridges use the separate {data, len} StringVal pair.
 * ============================================================================ */

/* StringVal layout. Used for {data*, len} pairs in dict comparisons and
 * internal value-passing. The ARC-managed String object now stores the
 * StringVal inline in its payload (no intermediate heap handle). */
typedef struct { char* data; int64_t len; } StringVal;

/* Inline payload of an ARC-managed String object.
 * Must match the Rolang struct
 * `String { var data: RawPtr; var length: i64; var hash_cache: i64 }`
 * in std/string.rl AND the payload_size baked into the string-literal
 * emission in compiler/codegen/backend.rl.
 * `hash` is the lazily memoized key hash (0 = not computed yet); string
 * contents are immutable after construction so it never goes stale. */
typedef struct {
    char* data;
    int64_t len;
    int64_t hash;
} StringPayload;

static inline StringVal rt_string_empty_val(void) {
    return (StringVal){NULL, 0};
}

static inline StringPayload* rt_string_payload(const void* string_obj) {
    if (string_obj == NULL) return NULL;
    return (StringPayload*)OBJ_PAYLOAD((void*)string_obj);
}

static inline StringVal rt_string_obj_value(const void* string_obj) {
    StringPayload* sp = rt_string_payload(string_obj);
    if (sp == NULL || sp->data == NULL) return rt_string_empty_val();
    return (StringVal){sp->data, sp->len};
}


void rt_string_destroy(StringVal s);
int64_t rt_str_len(StringVal s);
int64_t rt_str_is_empty(StringVal s);
int32_t rt_str_compare(StringVal a, StringVal b);
int32_t rt_str_contains(StringVal haystack, StringVal needle);
int32_t rt_str_starts_with(StringVal s, StringVal prefix);
int32_t rt_str_ends_with(StringVal s, StringVal suffix);
StringVal rt_str_concat(StringVal a, StringVal b);
StringVal rt_int_to_string(int64_t value);
StringVal rt_str_repeat(StringVal s, int32_t count);
int32_t rt_str_char_at(StringVal s, int32_t index);
int32_t rt_str_find_char(StringVal s, int32_t ch, int32_t start);
StringVal rt_str_substring(StringVal s, int32_t start, int32_t length);
int32_t _is_whitespace(char c);
StringVal rt_str_trim(StringVal s);
StringVal rt_str_replace(StringVal s, StringVal old, StringVal new_val);
StringVal rt_str_replace_self(StringVal s, StringVal old, StringVal new_val);
int64_t rt_str_to_i64(StringVal s);
int32_t rt_str_to_i32(StringVal s);
void* rt_str_split(StringVal s, StringVal sep);
void* rt_str_lines(StringVal s);
double rt_str_to_f64(StringVal s);
StringVal rt_f64_to_string(double val);
ROLANG_INTERNAL void* rl_string_handle_from_value(StringVal s);
void* rt_string_from_rodata(const char* data, int64_t len);
void rt_string_free_data(void* data);
void rt_string_free_handle(void* handle);
char* rt_string_handle_data(void* handle);
int64_t rt_string_handle_len(void* handle);
void rt_string_free_handle_only(void* handle);
void rt_string_release(void* s);
int64_t rt_string_len(void* s);
int64_t rt_string_is_empty(void* s);
int32_t rt_string_compare(void* a, void* b);
int32_t rt_string_contains(void* h, void* n);
int32_t rt_string_starts_with(void* s, void* p);
int32_t rt_string_ends_with(void* s, void* suffix);
void* rt_string_concat_handle(void* a, void* b);
void* rt_int_to_string_handle(int64_t value);
void* rt_u64_to_string_handle(uint64_t value);
void* rt_f64_to_string_handle(double value);
void* rt_f64_format_handle(double value, int32_t precision, int32_t style);
int32_t rt_string_find_from(void* haystack, void* needle, int32_t start);
int32_t rt_string_rfind(void* haystack, void* needle);
void* rt_string_repeat_handle(void* s, int32_t count);
int32_t rt_string_char_at(void* s, int32_t index);
int32_t rt_string_find_char(void* s, int32_t ch, int32_t start);
void* rt_string_substring_handle(void* s, int32_t start, int32_t len);
void* rt_string_trim_handle(void* s);
void* rt_string_replace_handle(void* s, void* old, void* new_val);
int64_t rt_string_to_i64(void* s);
int32_t rt_string_to_i32(void* s);
double rt_string_to_f64(void* s);

#endif /* ROLANG_STD_STRING_H */
