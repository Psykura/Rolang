#ifndef ROLANG_STD_VEC_H
#define ROLANG_STD_VEC_H

#include "../runtime/abi.h"
#include "string.h"

typedef struct {
    int32_t len;
    int32_t capacity;
    int32_t elem_size;
    int32_t elem_type_id;
} GVecHeader;

void rt_gvec_gc_trace(void* payload, GCTraceCb cb, void* ctx);
void* rt_gvec_new(int32_t capacity, int32_t elem_size, int32_t elem_type_id);
int32_t rt_gvec_len(void* vec);
int32_t rt_gvec_capacity(void* vec);
int32_t rt_gvec_elem_size(void* vec);
void rt_gvec_get(void* vec, int32_t index, void* out);
void rt_gvec_set(void* vec, int32_t index, const void* value);
void* rt_gvec_resize(void* vec, int32_t new_capacity);
void* rt_gvec_push(void* vec, const void* value);
void rt_gvec_pop(void* vec, void* out);
void rt_gvec_free(void* vec);

#endif /* ROLANG_STD_VEC_H */
