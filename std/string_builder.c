#include "../runtime/platform.h"
#include "string_builder.h"
#include "../runtime/api.h"

/* Growable byte buffer for compiler diagnostics and generated source/IR. */
typedef struct { char* data; size_t len, capacity; } StringBuilder;
void* rt_string_builder_new(void) {
    StringBuilder* b = calloc(1, sizeof(*b));
    if (!b) rt_panic("string builder allocation failed");
    return b;
}
static void string_builder_append(StringBuilder* b, const char* data, size_t len) {
    if (!b) rt_panic("null string builder");
    if (len > (size_t)INT64_MAX - b->len - 1) rt_panic("string builder too large");
    size_t needed = b->len + len + 1;
    if (needed > b->capacity) {
        size_t capacity = b->capacity ? b->capacity : 64;
        while (capacity < needed) {
            if (capacity > (size_t)INT64_MAX / 2) { capacity = needed; break; }
            capacity *= 2;
        }
        char* data_new = realloc(b->data, capacity);
        if (!data_new) rt_panic("string builder allocation failed");
        b->data = data_new; b->capacity = capacity;
    }
    if (len) memcpy(b->data + b->len, data, len);
    b->len += len; b->data[b->len] = 0;
}
void rt_string_builder_append(void* ptr, void* text) {
    StringVal value = rt_string_obj_value(text);
    string_builder_append(ptr, value.data, (size_t)value.len);
}
void rt_string_builder_byte(void* ptr, uint8_t value) {
    char byte = (char)value; string_builder_append(ptr, &byte, 1);
}
int64_t rt_string_builder_len(void* ptr) { return (int64_t)((StringBuilder*)ptr)->len; }
void rt_string_builder_clear(void* ptr) {
    StringBuilder* b = ptr; b->len = 0;
    if (b->data) b->data[0] = 0;
}
void* rt_string_builder_text(void* ptr) {
    StringBuilder* b = ptr;
    char* copy = malloc(b->len + 1);
    if (!copy) rt_panic("string builder allocation failed");
    if (b->len) memcpy(copy, b->data, b->len);
    copy[b->len] = 0;
    return rl_string_handle_from_value((StringVal){copy, (int64_t)b->len});
}
void rt_string_builder_free(void* ptr) {
    if (ptr) { StringBuilder* b = ptr; free(b->data); free(b); }
}
