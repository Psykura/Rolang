#include "collections.h"
#include "../runtime/platform.h"
#include "vec.h"
#include "../runtime/api.h"

// ============================================================================
// Generic dynamic vectors (for generic Vec<T>)
// Layout: { int32_t len, int32_t capacity, int32_t elem_size,
//           int32_t elem_type_id, data... }
//
// elem_type_id is the type descriptor index for the element type.
// 0 = primitive value type (i32, i64, f64, etc.) — no retain/release needed.
// Non-zero = heap type (struct, enum, tuple) — retain/release elements on push/pop/set/free.
// ============================================================================

/** Retain a heap-typed element stored at *elem_ptr if elem_type_id != 0. */
static inline void _gvec_retain_element(int32_t elem_type_id, const void* elem_ptr) {
    if (elem_type_id == 0 || elem_ptr == NULL) return;
    void* obj = *(void**)elem_ptr;
    if (obj != NULL) {
        rt_obj_retain(obj);
    }
}

/** Release a heap-typed element stored at *elem_ptr if elem_type_id != 0. */
static inline void _gvec_release_element(int32_t elem_type_id, void* elem_ptr) {
    if (elem_type_id == 0 || elem_ptr == NULL) return;
    void* obj = *(void**)elem_ptr;
    if (obj != NULL) {
        rt_obj_release(obj);
    }
}

/** Release all heap-typed elements in a vec, then free the vec. */
static void _gvec_release_all(GVecHeader* h) {
    if (h->elem_type_id == 0) return;
    unsigned char* data = (unsigned char*)(h + 1);
    for (int32_t i = 0; i < h->len; i++) {
        void* obj = *(void**)(data + (size_t)i * (size_t)h->elem_size);
        if (obj != NULL) {
            rt_obj_release(obj);
        }
    }
}

/*
 * GC trace hook for ``Vec<T>``. Codegen installs this on every
 * monomorphized ``Vec_*`` type's ``TypeDescriptor.trace_fn`` so the
 * cycle collector can reach into the runtime-allocated buffer that
 * the ``handle: RawPtr`` field points at.
 *
 * ``payload`` is the Rolang struct payload — by layout the first 8
 * bytes are the ``handle`` pointer (the rest are primitive fields
 * irrelevant to the GC).
 */
void rt_gvec_gc_trace(void* payload, GCTraceCb cb, void* ctx) {
    if (payload == NULL || cb == NULL) return;
    void* handle = *(void**)payload;
    if (handle == NULL) return;

    GVecHeader* h = (GVecHeader*)handle;
    /* elem_type_id == 0 means the buffer holds primitive bytes — no
     * managed pointers to trace. */
    if (h->elem_type_id == 0) return;
    if (h->len <= 0 || h->elem_size <= 0) return;

    unsigned char* data = (unsigned char*)(h + 1);
    for (int32_t i = 0; i < h->len; i++) {
        void* slot = *(void**)(data + (size_t)i * (size_t)h->elem_size);
        if (slot != NULL) {
            cb(slot, ctx);
        }
    }
}

void* rt_gvec_new(int32_t capacity, int32_t elem_size, int32_t elem_type_id) {
    if (capacity < 4) capacity = 4;
    if (elem_size <= 0) elem_size = 1;
    size_t total = sizeof(GVecHeader) + (size_t)capacity * (size_t)elem_size;
    GVecHeader* h = (GVecHeader*)malloc(total);
    if (!h) return NULL;
    h->len = 0;
    h->capacity = capacity;
    h->elem_size = elem_size;
    h->elem_type_id = elem_type_id;
    return h;
}

int32_t rt_gvec_len(void* vec) {
    if (!vec) return 0;
    return ((GVecHeader*)vec)->len;
}

int32_t rt_gvec_capacity(void* vec) {
    if (!vec) return 0;
    return ((GVecHeader*)vec)->capacity;
}

int32_t rt_gvec_elem_size(void* vec) {
    if (!vec) return 0;
    return ((GVecHeader*)vec)->elem_size;
}

void rt_gvec_get(void* vec, int32_t index, void* out) {
    if (!vec || !out) rt_panic("gvec_get on null vec or out pointer");
    GVecHeader* h = (GVecHeader*)vec;
    if (index < 0 || index >= h->len) {
        rt_panic_index_out_of_bounds((int64_t)index, (int64_t)h->len);
    }
    unsigned char* data = (unsigned char*)(h + 1);
    void* slot = data + (size_t)index * (size_t)h->elem_size;
    _rt_copy_small(out, slot, (size_t)h->elem_size);
    /* Retain heap-typed elements for the caller. The vec still owns the
     * slot, so the caller's `out` becomes a fresh strong reference. Without
     * this, dropping `out` would call rt_obj_release on a slot the vec
     * still references — UAF on the next vec destruction. */
    _gvec_retain_element(h->elem_type_id, out);
}

void rt_gvec_set(void* vec, int32_t index, const void* value) {
    if (!vec || !value) rt_panic("gvec_set on null vec or value");
    GVecHeader* h = (GVecHeader*)vec;
    if (index < 0 || index >= h->len) {
        rt_panic_index_out_of_bounds((int64_t)index, (int64_t)h->len);
    }

    /* Release old element if heap-typed */
    unsigned char* data = (unsigned char*)(h + 1);
    void* slot = data + (size_t)index * (size_t)h->elem_size;
    _gvec_release_element(h->elem_type_id, slot);

    /* Copy new value */
    memcpy(slot, value, (size_t)h->elem_size);

    /* Retain new element if heap-typed */
    _gvec_retain_element(h->elem_type_id, slot);
}

void* rt_gvec_resize(void* vec, int32_t new_capacity) {
    if (!vec || new_capacity <= 0) return vec;
    GVecHeader* h = (GVecHeader*)vec;
    if (new_capacity <= h->capacity) return vec;
    size_t elem_size = (size_t)h->elem_size;
    size_t new_data_size = (size_t)new_capacity * elem_size;
    size_t total = sizeof(GVecHeader) + new_data_size;
    GVecHeader* new_h = (GVecHeader*)realloc(h, total);
    if (!new_h) return vec;
    new_h->capacity = new_capacity;
    return new_h;
}

void* rt_gvec_push(void* vec, const void* value) {
    if (!vec || !value) return vec;
    GVecHeader* h = (GVecHeader*)vec;
    if (h->len >= h->capacity) {
        /* ``h->capacity * 2`` is signed int32 multiplication and wraps to
         * a negative value when capacity exceeds INT32_MAX/2. Detect
         * saturation explicitly and panic — exceeding 2^31 elements in a
         * single Vec is a real bug
         * either way. */
        int32_t cap = h->capacity;
        int32_t new_cap;
        if (cap >= (INT32_MAX / 2)) {
            if (cap >= INT32_MAX) {
                rt_panic("Vec capacity exceeds INT32_MAX");
            }
            new_cap = INT32_MAX;
        } else {
            new_cap = cap * 2;
        }
        if (new_cap < 8) new_cap = 8;
        vec = rt_gvec_resize(vec, new_cap);
        h = (GVecHeader*)vec;
        if (h->capacity <= h->len) {
            rt_panic("rt_gvec_push: resize failed to grow Vec capacity");
        }
    }
    unsigned char* data = (unsigned char*)(h + 1);
    void* slot = data + (size_t)h->len * (size_t)h->elem_size;
    memcpy(slot, value, (size_t)h->elem_size);
    _gvec_retain_element(h->elem_type_id, slot);
    h->len++;
    return vec;
}

void rt_gvec_pop(void* vec, void* out) {
    if (!vec || !out) return;
    GVecHeader* h = (GVecHeader*)vec;
    if (h->len <= 0) {
        /* Empty pop: zero the caller's slot. */
        unsigned char* eh = (unsigned char*)h;
        (void)eh;
        memset(out, 0, (size_t)h->elem_size);
        return;
    }
    h->len--;
    unsigned char* data = (unsigned char*)(h + 1);
    void* slot = data + (size_t)h->len * (size_t)h->elem_size;
    memcpy(out, slot, (size_t)h->elem_size);
    /* Ownership transfer: the slot's strong reference moves to the caller
     * via `out`. Do NOT release the slot here — doing so would leave the
     * caller with a dangling pointer in the common case where the vec was
     * the only owner. We do, however, zero the now-vacated slot so a later
     * push doesn't reuse a stale pointer that ARC might confuse for a
     * still-live reference. */
    memset(slot, 0, (size_t)h->elem_size);
}

void rt_gvec_free(void* vec) {
    if (!vec) return;
    GVecHeader* h = (GVecHeader*)vec;
    _gvec_release_all(h);
    free(vec);
}
