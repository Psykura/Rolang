#ifndef ROLANG_STD_DICT_H
#define ROLANG_STD_DICT_H

#include "../runtime/abi.h"
#include "string.h"


void* rt_dict_new(int64_t capacity, int64_t key_size, int64_t value_size,
                  int32_t key_kind, int32_t key_type_id, int32_t value_type_id);
void* rt_dict_resize(void* dict_ptr, int64_t new_capacity);
void* rt_dict_set(void* dict_ptr, const void* key, const void* value);
int32_t rt_dict_get(void* dict_ptr, const void* key, void* out);
void* rt_dict_entry_index(void* dict_ptr, const void* key,
                          const void* default_value, void* out_index);
void rt_dict_get_at(void* dict_ptr, int64_t index, void* out);
void rt_dict_set_at(void* dict_ptr, int64_t index, const void* value);
int32_t rt_dict_remove(void* ptr, const void* key, void* out);
void rt_dict_clear(void* ptr);
int64_t rt_dict_len(void* dict_ptr);
void* rt_dict_key_ptr(void* dict_ptr, int64_t index);
void rt_dict_key_copy(void* dict_ptr, int64_t index, void* out);
uint64_t rt_string_hash(void* string);
uint64_t rt_f64_bits(double value);
void* rt_dict_value_ptr(void* dict_ptr, int64_t index);
void rt_dict_free(void* dict_ptr);
void rt_dict_gc_trace(void* payload, GCTraceCb cb, void* ctx);

#endif /* ROLANG_STD_DICT_H */
