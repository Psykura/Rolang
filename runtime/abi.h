#ifndef ROLANG_RUNTIME_ABI_H
#define ROLANG_RUNTIME_ABI_H

#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>
#if defined(__GNUC__)
#define ROLANG_INTERNAL __attribute__((visibility("hidden")))
#else
#define ROLANG_INTERNAL
#endif

#define _OBJ_HEADER_SIZE 32
/* ============================================================================
 * Typed-Object System
 *
 * Every heap-allocated struct/enum/tuple has this layout:
 *
 *   Offset 0:  int64_t          rc           Reference count
 *   Offset 8:  uint64_t         type_id      Index into descriptor table
 *   Offset 16: struct ObjHeader* prev         GC list back-link (doubly-linked)
 *   Offset 24: struct ObjHeader* next         GC list forward-link
 *   Offset 32: <payload>                     Actual struct/enum/tuple data
 *
 * The payload starts at OBJ_HEADER_SIZE (32 bytes on 64-bit).
 * ============================================================================ */


typedef struct ObjHeader {
    int64_t           rc;          /* refcount. Non-atomic under
                                    * ROLANG_SINGLE_THREADED (default); undefine
                                    * that flag to restore atomics if a
                                    * multi-threaded runtime is ever added. */
    uint64_t          type_id;
    struct ObjHeader* prev;        /* gc_object_list back-link (NULL at head).
                                    * Reuses the reserved _pad slot so
                                    * gc_list_remove is O(1) instead of an O(n)
                                    * scan. Pool metadata is recovered at free
                                    * from the type descriptor. */
    struct ObjHeader* next;        /* gc_object_list forward-link */
} ObjHeader;

_Static_assert(offsetof(ObjHeader, rc) == 0,
    "inline retain/release IR assumes rc is the first header field (offset 0)");

#define OBJ_HEADER_SIZE  ((int64_t)sizeof(ObjHeader))
#define OBJ_HEADER(ptr)  ((ObjHeader*)(ptr))
#define OBJ_PAYLOAD(ptr) ((void*)((char*)(ptr) + OBJ_HEADER_SIZE))

/* The pool sizes objects before ObjHeader is defined, so it carries its own
 * header-size literal. Tie it to the real struct so the two can never drift —
 * and so resizing the header is caught here instead of corrupting the heap.
 * NOTE: compiler/codegen/ bakes the same payload offset; its layout constants
 * must be changed in lockstep (no cross-
 * language assert can guard it). */
_Static_assert(_OBJ_HEADER_SIZE == sizeof(ObjHeader),
    "_OBJ_HEADER_SIZE (pool) must equal sizeof(ObjHeader); also update "
    "the header offset in compiler/codegen/ to match the payload offset");

/* ============================================================================
 * Type Descriptors
 *
 * Each struct/enum type gets a static TypeDescriptor emitted by the codegen.
 * The GC uses these to find pointer fields within objects.
 * ============================================================================ */

typedef struct {
    int32_t  offset;        /* Byte offset of this field within the payload */
    uint64_t field_type_id; /* Descriptor id for the pointed-to field type */
    int32_t  case_tag;      /* -1 = struct/tuple field, >=0 = enum case tag */
    int32_t  _pad;
} FieldDescriptor;

/*
 * Pointer to a generated `void deinit(void* payload)` C ABI function or NULL.
 * If non-NULL, rt_obj_release calls it on the final reference-count
 * decrement, BEFORE releasing the object's pointer fields. This lets user
 * `deinit { ... }` blocks observe the object in a still-valid state.
 *
 * MUST stay in sync with the LLVM struct layout emitted by codegen in
 * compiler/codegen/backend.rl.
 */
typedef void (*DeinitFn)(void* payload);

/*
 * Optional cycle-collector trace hook. ``trace_fn`` is called by the GC
 * for any type whose managed pointers are not described by the static
 * field-descriptor list — most notably ``Vec<T>`` and ``Dict<K, V>``,
 * whose heap-typed slots live inside a separately-allocated buffer
 * reached through a ``RawPtr`` field that the descriptor table cannot
 * see into. The trace function receives the object's payload pointer
 * and a callback to invoke for every heap-typed managed pointer it can
 * find. ``ctx`` is opaque to the trace function and forwarded verbatim.
 */
typedef void (*GCTraceCb)(void* target, void* ctx);
typedef void (*GCTraceFn)(void* payload, GCTraceCb cb, void* ctx);

/*
 * Pointer to a codegen-generated `void release_fields(void* payload)` that
 * ARC-releases this type's heap pointer fields directly, with constant
 * offsets baked in — a specialized, branch-predictable replacement for the
 * generic obj_release_fields descriptor walk on the hot teardown path. NULL
 * for types with no heap fields (and for the weak default table); the runtime
 * then falls back to obj_release_fields, which no-ops when field_count == 0.
 * Generated from the SAME field-descriptor data, so it is exactly equivalent.
 */
typedef void (*ReleaseFieldsFn)(void* payload);

typedef struct {
    uint64_t        type_id;       /* Unique ID for this type */
    int64_t         payload_size;  /* Size of the data after the header */
    int32_t         field_count;   /* Number of pointer fields */
    int32_t         fields_start;  /* Start index in RT_TYPE_FIELD_DESCRIPTORS */
    DeinitFn        deinit_fn;     /* User deinit hook, or NULL */
    GCTraceFn       trace_fn;      /* Container GC trace hook, or NULL */
    int32_t         acyclic;       /* 1 = instances can never be in a cycle */
    ReleaseFieldsFn release_fields_fn; /* Per-type field-release fast path, or NULL.
                                        * Append-only: existing field offsets
                                        * (deinit_fn@24, trace_fn@32, acyclic@40)
                                        * are unchanged. */
} TypeDescriptor;

/* The LLVM desc_type in compiler/codegen/backend.rl emits these fields in this exact
 * order, with `acyclic` appended LAST. Guard the one field this change added:
 * if anyone inserts a field between trace_fn and acyclic, the runtime would
 * read acyclic at an offset codegen never wrote. Relational (not a hardcoded
 * offset) so it holds on any pointer width as long as the order is preserved. */
_Static_assert(offsetof(TypeDescriptor, acyclic)
                   == offsetof(TypeDescriptor, trace_fn) + sizeof(GCTraceFn),
    "TypeDescriptor.acyclic must immediately follow trace_fn to stay in sync "
    "with the LLVM desc_type emission in compiler/codegen/backend.rl");


#endif /* ROLANG_RUNTIME_ABI_H */
