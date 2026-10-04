#include "platform.h"
#include "api.h"

/* ============================================================================
 * Object Pool Allocator — lock-free free-list for small ARC objects
 * ============================================================================
 *
 * Every rt_obj_alloc call for objects ≤ 256 total bytes (header + payload)
 * is served from a per-size-class free-list. "From pool" is exactly
 * (total ≤ POOL_MAX_TOTAL_SIZE): small objects are always pooled (rt_obj_alloc
 * never OS-allocates them), so the free path recovers both that fact and the
 * size class from the type descriptor — nothing is stored per-object.
 * On deallocation, pooled objects are pushed back onto their free-list
 * instead of being returned to the OS.
 */
#define POOL_BIN_COUNT      6
#define POOL_MAX_TOTAL_SIZE 256
/* ObjHeader is 32 bytes on the 64-bit ABI; see abi.h. */

/* Size classes include the 32-byte object header. Tune using representative
 * allocation workloads and ROLANG_POOL_PROFILE. */
static const size_t pool_bin_sizes[POOL_BIN_COUNT] = {48, 64, 96, 128, 192, 256};

typedef struct PoolNode { struct PoolNode* __volatile next; } PoolNode;
/* The state the codegen-emitted inline allocation fast path (llvm_alloc_helper
 * in compiler/codegen/runtime.rl) reads and writes. Threaded runtimes keep it
 * in one thread-local struct, whose layout the generated code mirrors, so the
 * fast path computes one thread-local address; the names below then refer to
 * its fields. Older generated code links against the separate globals. */
#if defined(ROLANG_THREADED)
typedef struct RlHotState {
    PoolNode* volatile pool_free_lists[POOL_BIN_COUNT];  /* offset 0 */
    ObjHeader* gc_object_list;                           /* offset 48 */
    int64_t gc_alloc_counter;                            /* offset 56 */
    int64_t gc_trigger_at;                               /* offset 64 */
    volatile int gc_running;                             /* offset 72 */
    /* Not read by generated code; here so freeing an object computes one
     * thread-local address. */
    ObjHeader* gc_old_head;
} RlHotState;
__thread RlHotState rl_hot = { .gc_trigger_at = 10000 };
#define pool_free_lists (rl_hot.pool_free_lists)
#define gc_object_list (rl_hot.gc_object_list)
#define gc_alloc_counter (rl_hot.gc_alloc_counter)
#define gc_trigger_at (rl_hot.gc_trigger_at)
#define gc_running (rl_hot.gc_running)
#define gc_old_head (rl_hot.gc_old_head)
#else
PoolNode* volatile pool_free_lists[POOL_BIN_COUNT];
#endif

static int pool_bin_for_size(size_t total_size) {
    for (int i = 0; i < POOL_BIN_COUNT; i++) {
        if (total_size <= pool_bin_sizes[i]) return i;
    }
    return -1;
}

static void* pool_try_alloc(int bin) {
    PoolNode* node;
#if defined(ROLANG_SINGLE_THREADED)
    /* No concurrency: a plain pop is correct and avoids the atomic RMW that
     * dominates alloc-churn workloads (e.g. binary_trees). */
    node = pool_free_lists[bin];
    if (node == NULL) return NULL;
    pool_free_lists[bin] = node->next;
    return (void*)node;
#else
    /* Lock-free pop from singly-linked free list */
    do {
        node = pool_free_lists[bin];
        if (node == NULL) return NULL;
    } while (!__sync_bool_compare_and_swap(&pool_free_lists[bin], node, node->next));
    return (void*)node;
#endif
}

static void pool_free_object(void* ptr, size_t total_size) {
    int bin = pool_bin_for_size(total_size);
    if (bin < 0) return;
    PoolNode* node = (PoolNode*)ptr;
#if defined(ROLANG_SINGLE_THREADED)
    /* No concurrency: a plain push is correct (see pool_try_alloc). */
    node->next = pool_free_lists[bin];
    pool_free_lists[bin] = node;
#else
    PoolNode* head;
    /* Lock-free push onto singly-linked free list */
    do {
        head = pool_free_lists[bin];
        node->next = head;
    } while (!__sync_bool_compare_and_swap(&pool_free_lists[bin], head, node));
#endif
}

static void* pool_obj_alloc(size_t payload_size, int64_t align) {
    size_t total = (size_t)_OBJ_HEADER_SIZE + payload_size;
    if (total > POOL_MAX_TOTAL_SIZE) return NULL;

    int bin = pool_bin_for_size(total);
    if (bin < 0) return NULL;

    /* Round up to the bin's actual allocation size */
    size_t alloc_size = pool_bin_sizes[bin];

    void* obj = pool_try_alloc(bin);
    if (obj == NULL) {
        /* Pool empty; allocate from OS. Use the bin size (rounded up)
         * so later deallocs always hit the same bin. */
        /* Round allocation size up to the bin size and to alignment */
        size_t aligned_size = (alloc_size + ((size_t)align - 1)) & ~((size_t)align - 1);
        obj = aligned_alloc((size_t)align, aligned_size);
        if (obj == NULL) return NULL;
    }
    return obj;
}
/* ============================================================================*/

#ifdef ROLANG_POOL_PROFILE
/* ----------------------------------------------------------------------------
 * Allocation-size profiler. Build the runtime with -DROLANG_POOL_PROFILE to
 * record the total size (32-byte header + payload) of every typed-object
 * allocation into 16-byte buckets and dump a histogram at exit — the data that
 * drives the pool size-class table above. Compiled out of normal builds, so
 * leaving it in place is free. Single-threaded runtime → plain counters. */
#include <stdio.h>
#include <stdlib.h>
#define POOL_PROFILE_NBUCKETS 64        /* up to 1024 B in 16-byte steps */
static long rt_pool_profile_hist[POOL_PROFILE_NBUCKETS];
static long rt_pool_profile_over;
static int  rt_pool_profile_registered;
static void rt_pool_profile_dump(void) {
    long total = 0;
    for (int i = 0; i < POOL_PROFILE_NBUCKETS; i++) total += rt_pool_profile_hist[i];
    total += rt_pool_profile_over;
    if (total == 0) return;
    fprintf(stderr, "=== ROLANG POOL PROFILE (typed-object total = 32B header + payload) ===\n");
    long cum = 0;
    for (int i = 0; i < POOL_PROFILE_NBUCKETS; i++) {
        long c = rt_pool_profile_hist[i];
        if (c == 0) continue;
        cum += c;
        fprintf(stderr, "  %4d..%4d B : %10ld  (%5.1f%%, cum %5.1f%%)\n",
                i * 16, i * 16 + 15, c, 100.0 * c / total, 100.0 * cum / total);
    }
    if (rt_pool_profile_over)
        fprintf(stderr, "  > pool max   : %10ld  (%5.1f%%) [OS malloc path]\n",
                rt_pool_profile_over, 100.0 * rt_pool_profile_over / total);
    fprintf(stderr, "  total typed allocations: %ld\n", total);
}
static void rt_pool_profile_record(size_t total) {
    if (!rt_pool_profile_registered) {
        rt_pool_profile_registered = 1;
        atexit(rt_pool_profile_dump);
    }
    size_t b = total / 16;
    if (b < POOL_PROFILE_NBUCKETS) rt_pool_profile_hist[b]++;
    else rt_pool_profile_over++;
}
#endif /* ROLANG_POOL_PROFILE */

/* ============================================================================
 * Memory Management (raw allocation — unchanged)
 * ============================================================================ */

/**
 * Allocate memory with specified size and alignment.
 *
 * Used for internal allocations (frames, buffers, string data).
 * For typed heap objects, use rt_obj_alloc instead.
 *
 * @param size  Number of bytes to allocate
 * @param align Alignment requirement (power of 2)
 * @return Pointer to allocated memory, or NULL on failure
 */
void* rt_alloc(int64_t size, int64_t align) {
    if (size <= 0) {
        return NULL;
    }

    // aligned_alloc is C11 and present on every supported platform (glibc,
    // musl, macOS 10.15+). Using it unconditionally keeps rt_free a plain
    // free() everywhere, so pointers from rt_alloc AND from plain malloc
    // (e.g. runtime StringVal handles) can both be released through rt_free.
    // The old _POSIX_C_SOURCE-guarded fallback stashed the raw pointer at
    // ptr[-1]; on platforms that took it (macOS), rt_free then read garbage
    // when handed a plain-malloc'd pointer and aborted in libmalloc.
    // Ensure alignment is at least sizeof(void*) and size is a multiple of
    // alignment (C11 requires it). Cast sizeof(void*) to int64_t since
    // `align` is signed and an unsigned comparison would treat negative
    // values as huge positives.
    if (align < (int64_t)sizeof(void*)) {
        align = (int64_t)sizeof(void*);
    }
    // Round up size to be a multiple of alignment
    int64_t aligned_size = (size + align - 1) & ~(align - 1);
    return aligned_alloc((size_t)align, (size_t)aligned_size);
}

/**
 * Free previously allocated memory.
 *
 * @param ptr Pointer returned by rt_alloc (or NULL)
 */
void rt_free(void* ptr) {
    if (ptr == NULL) {
        return;
    }

    free(ptr);
}

/*
 * Global type descriptor table — flat array of TypeDescriptor structs.
 * Weak default; codegen provides the real table with strong definitions.
 */
__attribute__((weak))
TypeDescriptor RT_TYPE_DESCRIPTORS[1] = {{0, 0, 0, 0, NULL, NULL, 0, NULL}};
__attribute__((weak))
int32_t RT_TYPE_DESCRIPTOR_COUNT = 0;

/*
 * Flat array of field descriptors. RT_TYPE_DESCRIPTORS[i].fields_start
 * gives the starting index into this array; field_count gives the count.
 */
__attribute__((weak))
TypeHashFunctions RT_TYPE_HASH_FUNCTIONS[1] = {{NULL, NULL}};
__attribute__((weak))
int32_t RT_TYPE_HASH_FUNCTION_COUNT = 0;

__attribute__((weak))
FieldDescriptor RT_TYPE_FIELD_DESCRIPTORS[1] = {{0, 0, -1, 0}};
__attribute__((weak))
int32_t RT_TYPE_FIELD_DESCRIPTOR_COUNT = 0;

/* ============================================================================
 * Global Object Registry (for GC traversal)
 *
 * Singly-linked list of all live typed objects.  Protected by a spinlock.
 * ============================================================================ */

#if !defined(ROLANG_THREADED)
ObjHeader* gc_object_list = NULL;  /* non-static: see inline alloc fast path */
#endif
static atomic_flag gc_list_lock = ATOMIC_FLAG_INIT;

/* Generational boundary into gc_object_list (youngest at head):
 *   [gc_object_list .. gc_old_head)  = YOUNG (allocated since the last collect)
 *   [gc_old_head    .. NULL]         = OLD   (survived >=1 collection, tenured)
 * A *minor* collection scans only the young region; a *major* (every
 * GC_MAJOR_EVERY minors, and the very first collection) scans everything. This
 * keeps a large persistent cyclic-capable heap from being re-scanned on every
 * pass. Encoding the generation as list position avoids needing a per-object
 * field (the 32-byte ObjHeader is full). NULL means "all objects are young"
 * (forces a major). gc_list_remove maintains this boundary in O(1). */
#if !defined(ROLANG_THREADED)
static ObjHeader* gc_old_head = NULL;
#endif
static RL_TLS int        gc_minor_count = 0;
#ifndef GC_MAJOR_EVERY
#define GC_MAJOR_EVERY 8
#endif

#if !defined(ROLANG_THREADED)
int64_t gc_alloc_counter = 0;          /* non-static: inline alloc fast path */
#endif
RL_TLS int64_t gc_last_collect_count = 0;
static RL_TLS int64_t gc_cycle_count = 0;

/* Adaptive cycle-GC threshold. Instead of a fixed gap between collections,
 * scale the gap with the live set that survives each pass: a program with a
 * large persistent heap then amortizes each O(live) cycle scan over a
 * proportional number of subsequent allocations instead of rescanning every
 * GC_MIN_GAP allocations. Bounded by a floor and a cap. */
#ifndef GC_MIN_GAP
#define GC_MIN_GAP   10000
#endif
#ifndef GC_MAX_GAP
#define GC_MAX_GAP   8000000
#endif
#ifndef GC_GROWTH
#define GC_GROWTH    2
#endif
RL_TLS int64_t gc_next_gap = GC_MIN_GAP;
/* Precomputed trigger threshold: gc_last_collect_count + gc_next_gap. The
 * per-allocation poll is then one load + one compare against the counter.
 * Every site that updates the clock or the gap must refresh it. */
#if !defined(ROLANG_THREADED)
int64_t gc_trigger_at = GC_MIN_GAP;    /* non-static: inline alloc fast path */
#endif

/* ---- GC list lock helpers ---- */

/* Separately compiled modules register private descriptor tables before main.
 * Dense type tables remain the fast path for unified builds. */
typedef struct ModuleTypeEntry {
    TypeDescriptor descriptor_copy;
    TypeDescriptor* descriptor;
    TypeHashFunctions hash_functions;
    FieldDescriptor* fields;
    const char* key;
    struct ModuleTypeEntry* next;
} ModuleTypeEntry;
static ModuleTypeEntry** module_type_buckets;
static size_t module_type_capacity, module_type_count;
static ModuleTypeEntry* module_type_find(uint64_t id) {
    if (!module_type_capacity) return NULL;
    ModuleTypeEntry* e = module_type_buckets[id % module_type_capacity];
    while (e && e->descriptor->type_id != id) e = e->next;
    return e;
}
void rt_register_module_types(TypeDescriptor* descriptors, int32_t count,
                              FieldDescriptor* fields, int32_t field_count,
                              const char** keys) {
    for (int32_t i = 0; i < count; i++) {
        TypeDescriptor* d = &descriptors[i];
        if (d->fields_start < 0 || d->field_count < 0 ||
            (int64_t)d->fields_start + d->field_count > field_count)
            rt_panic("invalid module type descriptor");
        ModuleTypeEntry* existing = module_type_find(d->type_id);
        if (existing) {
            TypeDescriptor* old = existing->descriptor;
            if (strcmp(existing->key, keys[i]) || old->payload_size != d->payload_size ||
                old->field_count != d->field_count)
                rt_panic("module type identity collision or incompatible layout");
            for (int32_t j = 0; j < d->field_count; j++) {
                FieldDescriptor* a = &existing->fields[j];
                FieldDescriptor* b = &fields[d->fields_start + j];
                if (a->offset != b->offset || a->field_type_id != b->field_type_id || a->case_tag != b->case_tag)
                    rt_panic("incompatible module field layout");
            }
            /* The same layout can receive conservative metadata from an older
             * compiler or a different compilation context. Only skip cycle GC
             * when every registration proves acyclicity. Keep a writable copy
             * rather than modifying codegen's read-only descriptor globals. */
            old->acyclic = old->acyclic && d->acyclic;
            continue;
        }
        if (module_type_count * 2 >= module_type_capacity) {
            size_t capacity = module_type_capacity ? module_type_capacity * 2 : 256;
            ModuleTypeEntry** buckets = calloc(capacity, sizeof(*buckets));
            if (!buckets) rt_panic("module type registry allocation failed");
            for (size_t j = 0; j < module_type_capacity; j++) {
                ModuleTypeEntry* e = module_type_buckets[j];
                while (e) {
                    ModuleTypeEntry* next = e->next;
                    size_t slot = e->descriptor->type_id % capacity;
                    e->next = buckets[slot]; buckets[slot] = e; e = next;
                }
            }
            free(module_type_buckets);
            module_type_buckets = buckets; module_type_capacity = capacity;
        }
        ModuleTypeEntry* e = malloc(sizeof(*e));
        if (!e) rt_panic("module type registry allocation failed");
        size_t slot = d->type_id % module_type_capacity;
        e->descriptor_copy = *d; e->descriptor = &e->descriptor_copy;
        e->hash_functions.hash_fn = NULL; e->hash_functions.equals_fn = NULL;
        e->fields = d->field_count ? fields + d->fields_start : NULL;
        e->key = keys[i]; e->next = module_type_buckets[slot];
        module_type_buckets[slot] = e; module_type_count++;
    }
}

/* Hashable functions of separately compiled modules' types, registered after
 * their descriptors. */
void rt_register_module_hash_functions(TypeDescriptor* descriptors, TypeHashFunctions* functions, int32_t count) {
    for (int32_t i = 0; i < count; i++) {
        ModuleTypeEntry* entry = module_type_find(descriptors[i].type_id);
        if (entry && functions[i].hash_fn && functions[i].equals_fn) entry->hash_functions = functions[i];
    }
}

/* A type's Hashable functions, or NULL when it has none. */
static inline TypeHashFunctions* rt_get_type_hash_functions(uint64_t type_id) {
    TypeHashFunctions* functions = NULL;
    if (type_id < (uint64_t)RT_TYPE_HASH_FUNCTION_COUNT) functions = &RT_TYPE_HASH_FUNCTIONS[type_id];
    else if (type_id >= (uint64_t)RT_TYPE_DESCRIPTOR_COUNT) {
        ModuleTypeEntry* entry = module_type_find(type_id);
        if (entry) functions = &entry->hash_functions;
    }
    return functions && functions->hash_fn && functions->equals_fn ? functions : NULL;
}

static inline TypeDescriptor* rt_get_type_descriptor(uint64_t type_id) {
    if (type_id >= (uint64_t)RT_TYPE_DESCRIPTOR_COUNT) {
        ModuleTypeEntry* entry = module_type_find(type_id);
        return entry ? entry->descriptor : NULL;
    }
    return &RT_TYPE_DESCRIPTORS[type_id];
}

static inline int32_t rt_get_field_count(const TypeDescriptor* desc) {
    if (desc == NULL) return 0;
    return desc->field_count;
}

static inline FieldDescriptor* rt_get_field_descriptors(const TypeDescriptor* desc) {
    if (desc == NULL || desc->field_count == 0) return NULL;
    if (desc->type_id >= (uint64_t)RT_TYPE_DESCRIPTOR_COUNT) {
        ModuleTypeEntry* entry = module_type_find(desc->type_id);
        return entry ? entry->fields : NULL;
    }
    if (desc->fields_start < 0) return NULL;
    if (desc->fields_start + desc->field_count > RT_TYPE_FIELD_DESCRIPTOR_COUNT) return NULL;
    return &RT_TYPE_FIELD_DESCRIPTORS[desc->fields_start];
}

#if !defined(ROLANG_THREADED)
volatile int gc_running = 0;  /* Set to 1 during rt_gc_collect; non-static:
                               * inline alloc fast path reads it */
#endif

/* Defined below. rt_obj_alloc polls it once the alloc counter crosses the gap,
 * so the GC trigger lives at the one site allocations happen rather than being
 * polled before every statement by codegen. */
void rt_gc_collect(void);

static void gc_list_lock_acquire(void) {
#ifndef ROLANG_SINGLE_THREADED
    /* If GC is already running (called from within obj_release_fields
     * during step 5), don't re-acquire the lock — the GC holds it. */
    if (gc_running) return;
    while (atomic_flag_test_and_set_explicit(&gc_list_lock, memory_order_acquire)) {
        /* spin */
    }
#endif
    /* Single-threaded cooperative runtime: the GC list has no concurrent
     * accessors, so the per-allocation/-free lock is pure overhead. */
}

static void gc_list_lock_release(void) {
#ifndef ROLANG_SINGLE_THREADED
    if (gc_running) return;
    atomic_flag_clear_explicit(&gc_list_lock, memory_order_release);
#endif
}

/* ---- GC list operations ---- */

static void gc_list_add(ObjHeader* obj) {
    if (!gc_running) gc_list_lock_acquire();
    obj->prev = NULL;
    obj->next = gc_object_list;
    if (gc_object_list != NULL) gc_object_list->prev = obj;
    gc_object_list = obj;
    gc_alloc_counter++;
    if (!gc_running) gc_list_lock_release();
}

/* O(1) unlink from the doubly-linked gc_object_list. */
static void gc_list_remove(ObjHeader* obj) {
    if (!gc_running) gc_list_lock_acquire();
    ObjHeader* p = obj->prev;
    ObjHeader* n = obj->next;
    /* Keep the generational boundary valid if we unlink the first old object.
     * (During a collection gc_old_head is NULL, so this is a no-op then.) */
    if (obj == gc_old_head) gc_old_head = n;
    if (p != NULL) p->next = n;
    else           gc_object_list = n;   /* obj was the head */
    if (n != NULL) n->prev = p;
    obj->prev = NULL;
    obj->next = NULL;
    if (!gc_running) gc_list_lock_release();
}

/* ============================================================================
 * Typed-Object Allocation
 * ============================================================================ */

/**
 * Allocate a typed heap object.
 *
 * Allocates header + payload, initializes rc=1, sets type_id, links into
 * the GC registry.
 *
 * @param payload_size Size of the data payload in bytes
 * @param align        Alignment requirement (power of 2)
 * @param type_id      Index into RT_TYPE_DESCRIPTORS table
 * @return Pointer to the ObjHeader (start of the object), or NULL on failure
 */
static inline void* _obj_alloc_impl(int64_t payload_size, int64_t align,
                                    uint64_t type_id, int zero_payload) {
    int64_t total_size = OBJ_HEADER_SIZE + payload_size;

#ifdef ROLANG_POOL_PROFILE
    rt_pool_profile_record((size_t)total_size);
#endif

#ifdef ROLANG_CHECK_PAYLOAD
    {
        TypeDescriptor* _d = rt_get_type_descriptor(type_id);
        if (_d != NULL && _d->payload_size != payload_size) {
            fprintf(stderr, "ROLANG_CHECK_PAYLOAD type_id=%llu param=%lld desc=%lld\n",
                    (unsigned long long)type_id, (long long)payload_size,
                    (long long)_d->payload_size);
        }
    }
#endif

    /* Small objects ALWAYS come from the per-size-class pool; large ones from
     * the OS. Small objects do not fall back to rt_alloc on pool OOM (which
     * would yield a differently-sized block) — that keeps "from pool" exactly
     * equal to (total <= POOL_MAX_TOTAL_SIZE), so the free path can recover it
     * (and the pool bin) from the type descriptor without storing it here. */
    void* raw;
    if ((size_t)total_size <= POOL_MAX_TOTAL_SIZE) {
        raw = pool_obj_alloc((size_t)payload_size, align);
    } else {
        raw = rt_alloc(total_size, align);
    }
    if (raw == NULL) return NULL;

    ObjHeader* h = (ObjHeader*)raw;
    h->rc = 1;
    h->type_id = type_id;
    if (zero_payload && payload_size > 0) {
        if (payload_size <= 64) {
            /* Inline word stores instead of a memset libcall. Both the pool
             * (bin sizes) and rt_alloc (size rounded up to align) guarantee
             * the allocation extends to an 8-byte boundary past the payload,
             * so rounding the zero-fill up to a multiple of 8 stays in
             * bounds. */
            int64_t* p = (int64_t*)OBJ_PAYLOAD(h);
            int64_t words = (payload_size + 7) >> 3;
            for (int64_t i = 0; i < words; i++) p[i] = 0;
        } else {
            memset(OBJ_PAYLOAD(h), 0, (size_t)payload_size);
        }
    }

    gc_list_add(h);   /* sets h->prev and h->next */

    /* Trigger cycle-GC from the one place the allocation counter advances,
     * instead of polling before every statement in codegen. A reference cycle
     * can only be created by allocating a new heap object, so this is the only
     * point a check could ever fire — which lets non-allocating hot loops run
     * with zero GC overhead.
     *
     * The new object `h` is at this point the GC-list HEAD and, for a noinit
     * allocation, its payload still holds stale pool bytes — the caller's
     * field stores run only after we return. rt_gc_collect therefore SKIPS
     * the list head (see Step 1 there): the collector must never interpret
     * those stale bytes as pointer fields. Every OTHER listed object is
     * fully constructed (field stores are straight-line code right after
     * their allocation; there is no allocation, release, or suspension
     * point in between). The threshold test is inlined so the common case
     * stays a load+compare; skip entirely while a collection is already
     * running (a deinit-triggered allocation). */
    if (!gc_running && gc_alloc_counter >= gc_trigger_at) {
        rt_gc_collect();
    }

    return raw;
}

void* rt_obj_alloc(int64_t payload_size, int64_t align, uint64_t type_id) {
    return _obj_alloc_impl(payload_size, align, type_id, /*zero_payload=*/1);
}

/* Allocation WITHOUT the payload zero-fill, for construction sites that
 * provably store every live field before the next allocation, release, or
 * GC-observable point: MakeStruct (all fields required by the language) and
 * MakeEnum (tag + the active case's payload; every descriptor walk —
 * release_fields, GC trace, clone — is tag-filtered, so the inactive union
 * bytes are never read). The zero-fill is a meaningful fraction of
 * alloc-churn workloads (binary_trees); for fully-stored payloads it is
 * pure waste. Callers that leave any live field unwritten MUST use
 * rt_obj_alloc instead. */
void* rt_obj_alloc_noinit(int64_t payload_size, int64_t align, uint64_t type_id) {
    return _obj_alloc_impl(payload_size, align, type_id, /*zero_payload=*/0);
}

/* ============================================================================
 * Typed-Object Reference Counting
 * ============================================================================ */

/* Forward declaration — used by obj_release_fields for recursive field cleanup */
void rt_obj_release(void* ptr);

/* Cold path: rc has just reached 0. Runs deinit, handles resurrection,
 * releases pointer fields, unlinks from the GC list, and frees. */
void rt_obj_release_slow(void* ptr);

/**
 * Increment reference count of a typed heap object.
 */
void rt_obj_retain(void* ptr) {
    if (ptr == NULL) {
        return;
    }
#ifdef ROLANG_FREE_STATS
    { extern void rt_retain_stat(void); rt_retain_stat(); }
#endif

    int64_t* refcount = &OBJ_HEADER(ptr)->rc;

#if defined(ROLANG_SINGLE_THREADED)
    (*refcount)++;   /* single-threaded runtime: atomics are pure overhead */
#elif defined(__GNUC__) || defined(__clang__)
    __atomic_fetch_add(refcount, 1, __ATOMIC_RELAXED);
#else
    (*refcount)++;
#endif
}

/**
 * Release pointer fields of a typed object (called before freeing).
 */
static void obj_release_fields(ObjHeader* h) {
    TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
    if (desc == NULL) {
        return;
    }

    int32_t field_count = rt_get_field_count(desc);
    if (field_count <= 0) {
        return;
    }

    FieldDescriptor* fields = rt_get_field_descriptors(desc);
    if (fields == NULL) {
        return;
    }

    void* payload = OBJ_PAYLOAD(h);
    /* For enum objects, read the tag once so we can filter case-specific fields */
    int32_t enum_tag = 0;
    int32_t tag_available = 0;

    for (int32_t i = 0; i < field_count; i++) {
        FieldDescriptor* fd = &fields[i];
        /* For enum payload fields, check the tag matches the active case */
        if (fd->case_tag >= 0) {
            if (!tag_available) {
                enum_tag = *(int32_t*)payload;
                tag_available = 1;
            }
            if (enum_tag != fd->case_tag) {
                continue;  /* This field belongs to a different enum case */
            }
        }
        void** field_ptr = (void**)((char*)payload + fd->offset);
        if (*field_ptr != NULL) {
            rt_obj_release(*field_ptr);
        }
    }
}

/**
 * Decrement reference count of a typed heap object.
 * If rc reaches 0, IMMEDIATELY release all pointer fields and free the object.
 *
 * This is the PRIMARY deallocation path. The GC is never involved unless a
 * reference cycle prevents rc from ever reaching 0.
 */
void rt_obj_release(void* ptr) {
    if (ptr == NULL) {
        return;
    }
#ifdef ROLANG_FREE_STATS
    { extern void rt_release_stat(void); rt_release_stat(); }
#endif

    ObjHeader* h = OBJ_HEADER(ptr);
    int64_t prev;

#if defined(ROLANG_SINGLE_THREADED)
    prev = (h->rc)--;
#elif defined(__GNUC__) || defined(__clang__)
    prev = __atomic_fetch_sub(&h->rc, 1, __ATOMIC_ACQ_REL);
#else
    prev = (h->rc)--;
#endif

    if (prev == 1) {
        rt_obj_release_slow(ptr);
    }
}

/**
 * Cold teardown path: the caller has already decremented rc to 0.
 * Split out of rt_obj_release so codegen can inline only the hot
 * null-check + decrement + compare and call here only when rc hits 0.
 * Performs NO decrement of its own.
 */
#ifdef ROLANG_FREE_STATS
static long rt_free_count, rt_free_rc_nonzero, rt_retain_n, rt_release_n;
static int  rt_free_reg;
static void rt_free_dump(void) {
    fprintf(stderr, "=== FREE STATS === retains=%ld releases=%ld slow_frees=%ld (rc!=0: %ld)\n",
            rt_retain_n, rt_release_n, rt_free_count, rt_free_rc_nonzero);
}
static void rt_free_reg_once(void) { if (!rt_free_reg) { rt_free_reg = 1; atexit(rt_free_dump); } }
void rt_free_stat(int64_t rc_now) {
    rt_free_reg_once();
    rt_free_count++;
    if (rc_now != 0) rt_free_rc_nonzero++;
}
void rt_retain_stat(void) { rt_free_reg_once(); rt_retain_n++; }
void rt_release_stat(void) { rt_free_reg_once(); rt_release_n++; }
#endif

void rt_obj_release_slow(void* ptr) {
    ObjHeader* h = OBJ_HEADER(ptr);

#ifdef ROLANG_FREE_STATS
    {
        extern void rt_free_stat(int64_t rc_now);
        rt_free_stat(h->rc);
    }
#endif

    /* rc reached 0 — immediate free, no GC delay.
     *
     * Order matters:
     *   1. Run the user-declared `deinit` (if any) while the object is
     *      still fully valid — fields not yet released, pointer still
     *      live. This lets the deinit body call methods on `self`,
     *      access fields, etc.
     *   2. Detect deinit-resurrection: if the body stashed `self` in a
     *      reachable location (global, container) and retained, the
     *      object must NOT be freed — mirrors the cycle-GC behaviour
     *      in Phase 5c.
     *   3. Release pointer fields recursively (drops their refcounts).
     *   4. Unlink from GC list and free the allocation.
     */
    TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
    if (desc != NULL && desc->deinit_fn != NULL) {
        /* Pin rc to a sentinel value so any retain/release inside the
         * deinit observes a large positive count and cannot re-enter
         * the ``prev == 1`` branch via a balanced retain+release pair. */
        const int64_t PIN = (int64_t)0x4000000000000000LL;
        __atomic_store_n(&h->rc, PIN, __ATOMIC_RELAXED);
        desc->deinit_fn(ptr);
        int64_t cur = __atomic_load_n(&h->rc, __ATOMIC_RELAXED);
        int64_t extra = cur - PIN;
        if (extra > 0) {
            /* Resurrected — leave the object alive with the new rc and
             * skip teardown. The GC cycle path uses the same trick. */
            __atomic_store_n(&h->rc, extra, __ATOMIC_RELAXED);
            return;
        }
        /* Restore rc to 0 before tearing down so any debug introspection
         * sees the expected state. */
        __atomic_store_n(&h->rc, 0, __ATOMIC_RELAXED);
    }
    /* Release all pointer fields recursively. Prefer the codegen-generated
     * per-type fast path (constant offsets, no descriptor walk); fall back to
     * the generic walk for the weak default table / any type without one. */
    if (desc != NULL && desc->release_fields_fn != NULL) {
        desc->release_fields_fn(OBJ_PAYLOAD(h));
    } else {
        obj_release_fields(h);
    }
    gc_list_remove(h);       /* Remove from GC registry (O(1)) */
    /* Recover the pool bin from the type descriptor instead of a stored _pad:
     * total = header + payload, and rt_obj_alloc guarantees small objects
     * (total <= POOL_MAX_TOTAL_SIZE) are always pooled. If the descriptor is
     * missing (should not happen for a live object), free directly — pooled
     * blocks are aligned_alloc'd, so free() is valid. */
    int64_t total = (desc != NULL) ? (OBJ_HEADER_SIZE + desc->payload_size) : 0;
    if (desc != NULL && total <= (int64_t)POOL_MAX_TOTAL_SIZE) {
        pool_free_object(ptr, (size_t)total);
    } else {
        rt_free(ptr);
    }
}

/* ============================================================================
 * Object Cloning
 * ============================================================================ */

/**
 * Copy a typed heap object, retaining its managed fields.
 *
 * Allocates a new object with the same type descriptor, copies the payload
 * byte-for-byte, and retains all pointer fields.
 */
void* rt_obj_clone(void* ptr) {
    if (ptr == NULL) {
        return NULL;
    }

    ObjHeader* src = OBJ_HEADER(ptr);

    TypeDescriptor* desc = rt_get_type_descriptor(src->type_id);
    if (desc == NULL) {
        return NULL;
    }

    /* Allocate clone with same alignment as source.
     * Compute alignment from payload_size: round up to next power of 2,
     * capped at 16.  For vector/SIMD types the type descriptor can be
     * extended with an alignment field later. */
    int64_t align = 8;
    if (desc->payload_size > 8) align = 16;
    void* clone = rt_obj_alloc(desc->payload_size, align, src->type_id);
    if (clone == NULL) {
        return NULL;
    }

    /* Copy payload */
    memcpy(OBJ_PAYLOAD(clone), OBJ_PAYLOAD(ptr), (size_t)desc->payload_size);

    /* Retain all pointer fields in the clone */
    int32_t field_count = rt_get_field_count(desc);
    FieldDescriptor* fields = rt_get_field_descriptors(desc);
    if (field_count > 0 && fields != NULL) {
        void* clone_payload = OBJ_PAYLOAD(clone);
        int32_t enum_tag = 0;
        int32_t tag_available = 0;

        for (int32_t i = 0; i < field_count; i++) {
            FieldDescriptor* fd = &fields[i];
            if (fd->case_tag >= 0) {
                if (!tag_available) {
                    enum_tag = *(int32_t*)clone_payload;
                    tag_available = 1;
                }
                if (enum_tag != fd->case_tag) {
                    continue;
                }
            }
            void** field_ptr = (void**)((char*)clone_payload + fd->offset);
            if (*field_ptr != NULL) {
                rt_obj_retain(*field_ptr);
            }
        }
    }

    return clone;
}

/* ============================================================================
 * Cycle-Detecting GC
 *
 * The GC exists solely to detect and collect reference cycles. All non-cyclic
 * objects are already freed immediately by rt_obj_release when their rc hits 0.
 *
 * Algorithm: Synchronous trial deletion
 *
 *   1. Build candidate set from all live typed objects (skip rc==0)
 *   2. Subtract internal references (temporarily decrement rc for pointers
 *      between candidates)
 *   3. Objects with rc==0 are unreachable cycle members → collect
 *   4. Restore refcounts for survivors
 *   5. Free collected objects via rt_obj_release
 *
 * Thread safety: Stop-the-world (acquires gc_list_lock for duration).
 * ============================================================================ */

/* Temporary tracking per object during GC.
 *
 * The candidate buffer (and accompanying open-addressing hash table) grows
 * dynamically. */

typedef struct {
    ObjHeader* obj;
    int64_t   saved_rc;       /* Original rc before trial deletion */
    int32_t   collected;      /* 1 if marked for collection */
    int32_t   _pad;
} GCCandidate;

/* During a collection, candidate membership and reachability are tracked as
 * high bits stashed directly in each candidate's rc field, replacing the
 * previous pointer->index hash table: a membership test becomes one load+mask
 * on memory the collector touches anyway (no hashing, no probe chain, and no
 * table to memset every pass). The low 61 bits remain the trial refcount —
 * real refcounts can never approach 2^61, so the bits are unambiguous.
 * Survivors get their exact rc restored from saved_rc (clearing both bits);
 * collected objects carry their bits until pinned (deinit path) or freed. */
#define GC_CAND_BIT      ((int64_t)1 << 62)
#define GC_REACH_BIT     ((int64_t)1 << 61)
#define GC_RC_VALUE_MASK (GC_REACH_BIT - 1)

#define GC_INITIAL_CAPACITY 4096

static RL_TLS GCCandidate* gc_candidates = NULL;
static RL_TLS int32_t gc_candidates_capacity = 0;
static RL_TLS int32_t gc_candidate_count = 0;
static RL_TLS ObjHeader** gc_worklist = NULL;
static RL_TLS int32_t gc_worklist_capacity = 0;

/* Survivor count at the end of the previous pass. Approximates the live
 * count of the old (tenured) region so a minor pass can derive a total live
 * figure for gap adaptation without walking the old region. Old objects
 * freed by refcounting between passes make this stale-high, which only
 * inflates the next gap slightly; every major pass recomputes it exactly. */
static RL_TLS int64_t gc_old_live_count = 0;

static int gc_buffers_ensure(int32_t needed) {
    /* Ensure the candidate / worklist buffers can hold at least `needed`
     * candidates. Returns 0 on success, -1 on alloc fail. */
    if (gc_candidates_capacity >= needed && gc_candidates != NULL) {
        return 0;
    }
    int32_t new_cap = gc_candidates_capacity > 0 ? gc_candidates_capacity : GC_INITIAL_CAPACITY;
    while (new_cap < needed) {
        if (new_cap > INT32_MAX / 2) {
            /* About to overflow — clamp and let the caller cope. */
            new_cap = INT32_MAX - 1;
            break;
        }
        new_cap *= 2;
    }
    GCCandidate* nc = (GCCandidate*)realloc(gc_candidates, (size_t)new_cap * sizeof(GCCandidate));
    if (nc == NULL) return -1;
    gc_candidates = nc;

    ObjHeader** nw = (ObjHeader**)realloc(gc_worklist, (size_t)new_cap * sizeof(ObjHeader*));
    if (nw == NULL) return -1;
    gc_worklist = nw;
    gc_worklist_capacity = new_cap;
    gc_candidates_capacity = new_cap;
    return 0;
}

/* ---- GC trace callbacks ----
 *
 * Plumbing for the optional ``TypeDescriptor.trace_fn`` hook. Container
 * types (Vec/Dict) invoke these via their ``trace_fn`` so the cycle
 * collector can reach into a runtime-allocated buffer that the static
 * FieldDescriptor list cannot describe. The callbacks read and update
 * the same ``gc_candidates`` / ``gc_index`` state that the inline
 * FieldDescriptor walk uses.
 */
static void gc_subtract_cb(void* target, void* ctx) {
    (void)ctx;
    if (target == NULL) return;
    ObjHeader* th = OBJ_HEADER(target);
    if (th->rc & GC_CAND_BIT) {
        th->rc--;
    }
}

static void gc_mark_cb(void* target, void* ctx) {
    int32_t* work_count_p = (int32_t*)ctx;
    if (work_count_p == NULL || target == NULL) return;
    ObjHeader* th = OBJ_HEADER(target);
    if ((th->rc & GC_CAND_BIT) && !(th->rc & GC_REACH_BIT)) {
        th->rc |= GC_REACH_BIT;
        gc_worklist[(*work_count_p)++] = th;
    }
}

#ifdef ROLANG_GC_STATS
static long gc_st_minors, gc_st_majors, gc_st_min_c, gc_st_maj_c, gc_st_min_l, gc_st_maj_l;
static int  gc_st_reg;
static void gc_stats_dump(void) {
    fprintf(stderr, "=== GC STATS ===\n");
    fprintf(stderr, "  minors=%ld cand_sum=%ld live_walked_sum=%ld\n",
            gc_st_minors, gc_st_min_c, gc_st_min_l);
    fprintf(stderr, "  majors=%ld cand_sum=%ld live_walked_sum=%ld\n",
            gc_st_majors, gc_st_maj_c, gc_st_maj_l);
}
void rt_gc_stats_record(int is_major, int live, int cands) {
    if (!gc_st_reg) { gc_st_reg = 1; atexit(gc_stats_dump); }
    if (is_major) { gc_st_majors++; gc_st_maj_c += cands; gc_st_maj_l += live; }
    else          { gc_st_minors++; gc_st_min_c += cands; gc_st_min_l += live; }
}
#endif

/**
 * Trigger cycle-detection GC.
 *
 * Only called periodically (e.g. every 10k allocations) or on explicit request.
 * Collects unreachable reference cycles that rt_obj_release can't detect.
 */
void rt_gc_collect(void) {
    /* Early return if not enough allocations since last collection.
     * Check without the full lock to avoid overhead on every GCCheck. */
    if (gc_alloc_counter - gc_last_collect_count < gc_next_gap) {
        return;
    }

    /* Re-entrancy guard: if a ``deinit`` running inside an active GC pass
     * triggers another ``rt_gc_collect`` (e.g. by allocating enough to push
     * gc_alloc_counter past the next threshold), we must NOT try to acquire
     * the spinlock we are already holding — that would deadlock. Every
     * other helper (gc_list_add, gc_list_remove, etc.) already short-circuits
     * when ``gc_running`` is set. */
    if (gc_running) {
        return;
    }

    while (atomic_flag_test_and_set_explicit(&gc_list_lock, memory_order_acquire)) {
        /* spin */
    }
    /* Double-check after acquiring the lock: another thread (in a future
     * multi-threaded runtime) might have set gc_running between our load
     * and the lock acquisition. Today this is impossible, but keeps the
     * invariant honest. */
    if (gc_running) {
        atomic_flag_clear_explicit(&gc_list_lock, memory_order_release);
        return;
    }
    gc_running = 1;

    /* Decide minor (young region only) vs major (whole list). The first
     * collection (gc_old_head == NULL) and every GC_MAJOR_EVERY-th minor are
     * major. `scan_end` bounds Step 1 to the young region for a minor. The
     * boundary is disabled (NULL) for the duration of the collection so
     * gc_list_remove no-ops on it, and re-established at the end — every
     * surviving object becomes old (tenured). Excluding old objects from a
     * minor's candidate set can only ADD apparent external references (an
     * old->young edge is not subtracted), so a minor under-collects at worst
     * (cross-generational / old-only cycles float until the next major) and can
     * never over-collect — the same safety property as the acyclic skip. */
    int is_major = (gc_old_head == NULL);
    if (!is_major && ++gc_minor_count >= GC_MAJOR_EVERY) is_major = 1;
    if (is_major) gc_minor_count = 0;
    ObjHeader* scan_end = is_major ? NULL : gc_old_head;
    gc_old_head = NULL;

    /* Step 1: Build the candidate set from the scanned region (young for a
     * minor, all for a major) in ONE walk, tagging each candidate's rc with
     * GC_CAND_BIT and counting the region's live objects as we go. The old
     * region's live count is carried over from the previous pass's survivor
     * count (gc_old_live_count), so no separate whole-list walk is needed.
     * Buffers grow on demand mid-walk; on allocation failure we proceed with
     * the partial candidate set — trial deletion over a subset treats refs
     * from outside the subset as external, so it under-collects at worst. */
    if (gc_buffers_ensure(GC_INITIAL_CAPACITY) != 0) {
        /* Out of memory creating the candidate buffer. Conservatively skip
         * this collection — better to leak a cycle than abort the program.
         * Restart the allocation clock: otherwise the trigger condition
         * stays permanently true and EVERY subsequent allocation re-enters
         * the collector (observed as a ~180x slowdown on allocation-heavy
         * acyclic workloads). */
        gc_old_head = gc_object_list;
        gc_last_collect_count = gc_alloc_counter;
        gc_trigger_at = gc_alloc_counter + gc_next_gap;
        gc_running = 0;
        atomic_flag_clear_explicit(&gc_list_lock, memory_order_release);
        return;
    }

    gc_candidate_count = 0;
    /* Whether ANY candidate's type declares a `deinit`. Collected objects are
     * always a subset of the candidates, so when this stays 0 the sweep can
     * skip the pin / deinit / resurrection phases and the defensive
     * field-nulling walk entirely (see Step 6). */
    int any_deinit = 0;
    int64_t young_live = 0;
    ObjHeader* obj = gc_object_list;
    /* SKIP the list head. The allocation-site trigger fires right after
     * gc_list_add, so the head is the object being allocated RIGHT NOW: for
     * a noinit allocation its payload is stale pool bytes (the caller's
     * field stores have not run yet), and the collector must never read
     * those as pointer fields. Excluding one object from candidacy only
     * under-collects (its refs into the candidate set are treated as
     * external), and the freshest allocation is never collectable anyway —
     * the constructing code holds its rc=1 reference. It still counts as
     * young+live for gap pacing. */
    if (obj != NULL && obj != scan_end) {
        if (obj->rc > 0) young_live++;
        obj = obj->next;
    }
    while (obj != scan_end) {
        if (obj->rc > 0) {
            young_live++;
            /* Acyclic-typed objects can never be part of a reference cycle, so
             * we exclude them from the candidate set. References *from* them to
             * candidates are then treated as external (keeping those candidates
             * alive), and the acyclic objects themselves are freed promptly by
             * refcounting in rt_obj_release, never by the collector. */
            TypeDescriptor* od = rt_get_type_descriptor(obj->type_id);
            if (od == NULL || !od->acyclic) {
                if (gc_candidate_count == gc_candidates_capacity &&
                    gc_buffers_ensure(gc_candidates_capacity + 1) != 0) {
                    break;  /* partial set: safe under-collection */
                }
                GCCandidate* c = &gc_candidates[gc_candidate_count++];
                c->obj = obj;
                c->saved_rc = obj->rc;
                c->collected = 0;
                obj->rc |= GC_CAND_BIT;
                if (od != NULL && od->deinit_fn != NULL) any_deinit = 1;
            }
        }
        obj = obj->next;
    }
    int64_t live_count = young_live + (is_major ? 0 : gc_old_live_count);

#ifdef ROLANG_GC_STATS
    {
        extern void rt_gc_stats_record(int is_major, int live, int cands);
        rt_gc_stats_record(is_major, (int)live_count, gc_candidate_count);
    }
#endif

    if (gc_candidate_count == 0) {
        gc_old_head = gc_object_list;   /* tenure: no cyclic candidates this pass */
        gc_old_live_count = live_count;
        /* Restart the allocation clock and adapt the gap exactly like the
         * normal epilogue (survivors == live_count: nothing was collected).
         * An all-acyclic live set hits this path on EVERY collection; without
         * the update the trigger stays armed and each subsequent allocation
         * pays a full collect preamble. */
        {
            int64_t gap = live_count * GC_GROWTH;
            if (gap < GC_MIN_GAP) gap = GC_MIN_GAP;
            if (gap > GC_MAX_GAP) gap = GC_MAX_GAP;
            gc_next_gap = gap;
        }
        gc_last_collect_count = gc_alloc_counter;
        gc_trigger_at = gc_alloc_counter + gc_next_gap;
        gc_running = 0;
        atomic_flag_clear_explicit(&gc_list_lock, memory_order_release);
        return;
    }

    /* Step 2: Subtract internal references (now O(n * avg_fields) total).
     *
     * Each candidate walks its static FieldDescriptor list AND, if the
     * type has a registered ``trace_fn`` (containers like Vec / Dict),
     * also walks dynamic pointers found inside an external buffer that
     * the static descriptor cannot see into. */
    for (int32_t i = 0; i < gc_candidate_count; i++) {
        ObjHeader* h = gc_candidates[i].obj;
        TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
        if (desc == NULL) continue;

        void* payload = OBJ_PAYLOAD(h);
        int32_t field_count = rt_get_field_count(desc);
        FieldDescriptor* fields = rt_get_field_descriptors(desc);

        if (field_count > 0 && fields != NULL) {
            int32_t enum_tag = 0;
            int32_t tag_available = 0;

            for (int32_t f = 0; f < field_count; f++) {
                FieldDescriptor* fd = &fields[f];
                if (fd->case_tag >= 0) {
                    if (!tag_available) {
                        enum_tag = *(int32_t*)payload;
                        tag_available = 1;
                    }
                    if ((int32_t)enum_tag != fd->case_tag) continue;
                }

                void* target = *(void**)((char*)payload + fd->offset);
                if (target == NULL) continue;

                ObjHeader* th = OBJ_HEADER(target);
                if (th->rc & GC_CAND_BIT) {
                    th->rc--;
                }
            }
        }

        if (desc->trace_fn != NULL) {
            desc->trace_fn(payload, gc_subtract_cb, NULL);
        }
    }

    /* Step 3: Mark every candidate reachable from an object that still has an
     * external reference. Trial deletion alone is not enough: if A has an
     * external ref and points to B, B's trial rc can fall to zero but B is
     * still reachable through A and must survive. */
    int32_t work_count = 0;
    for (int32_t i = 0; i < gc_candidate_count; i++) {
        ObjHeader* h = gc_candidates[i].obj;
        if ((h->rc & GC_RC_VALUE_MASK) > 0 && !(h->rc & GC_REACH_BIT)) {
            h->rc |= GC_REACH_BIT;
            gc_worklist[work_count++] = h;
        }
    }

    while (work_count > 0) {
        ObjHeader* h = gc_worklist[--work_count];
        TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
        if (desc == NULL) continue;

        void* payload = OBJ_PAYLOAD(h);
        int32_t field_count = rt_get_field_count(desc);
        FieldDescriptor* fields = rt_get_field_descriptors(desc);

        if (field_count > 0 && fields != NULL) {
            int32_t enum_tag = 0;
            int32_t tag_available = 0;

            for (int32_t f = 0; f < field_count; f++) {
                FieldDescriptor* fd = &fields[f];
                if (fd->case_tag >= 0) {
                    if (!tag_available) {
                        enum_tag = *(int32_t*)payload;
                        tag_available = 1;
                    }
                    if ((int32_t)enum_tag != fd->case_tag) continue;
                }

                void* target = *(void**)((char*)payload + fd->offset);
                if (target == NULL) continue;

                ObjHeader* th = OBJ_HEADER(target);
                if ((th->rc & GC_CAND_BIT) && !(th->rc & GC_REACH_BIT)) {
                    th->rc |= GC_REACH_BIT;
                    gc_worklist[work_count++] = th;
                }
            }
        }

        if (desc->trace_fn != NULL) {
            desc->trace_fn(payload, gc_mark_cb, &work_count);
        }
    }

    /* Step 4+5 (fused): identify garbage and restore survivor refcounts in
     * one scan. Restoring from saved_rc clears both GC bits on survivors;
     * collected objects keep their bits until pinned (deinit path) or freed. */
    int32_t collected_count = 0;
    for (int32_t i = 0; i < gc_candidate_count; i++) {
        GCCandidate* c = &gc_candidates[i];
        if (c->obj->rc & GC_REACH_BIT) {
            c->obj->rc = c->saved_rc;
        } else {
            c->collected = 1;
            collected_count++;
        }
    }

    /* Step 6: Collect garbage objects.
     *
     * Cleanup order is carefully chosen so user `deinit { ... }` blocks
     * observe the same well-defined state they get on the non-GC release
     * path: a fully-initialized `self` with intact pointer fields.
     *
     *   Phase 5a — Pin collected objects.
     *     Bump each collected object's rc to a high sentinel so any
     *     `rt_obj_retain` / `rt_obj_release` calls executed from inside
     *     a deinit (including a deinit that resurrects itself by stashing
     *     `self` somewhere reachable) cannot free it during the sweep.
     *
     *   Phase 5b — Run all deinits.
     *     Every deinit sees the full original graph, with pointer fields
     *     still pointing at the (still-valid) other collected objects.
     *     A deinit may mutate non-collected state freely.
     *
     *   Phase 5c — Resurrection check.
     *     If a deinit increased rc above the sentinel value, the object
     *     was published to surviving state. Skip its teardown so the
     *     surviving owner ends up with a live pointer.
     *
     *   Phase 5d — Unlink the (non-resurrected) collected objects from
     *     gc_object_list in one O(n) sweep.
     *
     *   Phase 5e — Release pointer fields and free memory.
     *     Field release happens *after* deinit so deinit could read them.
     */
    if (collected_count > 0) {
        gc_cycle_count += collected_count;

        /* Phases 5a-5c exist solely to give user `deinit` bodies a
         * well-defined view of the dying graph (and to catch resurrection).
         * When no candidate type has a deinit — the common case — they are
         * three wasted scans over the collected set; skip them outright. */
        if (any_deinit) {

        /* Phase 5a: Pin all collected objects so deinit-side ARC traffic
         * cannot cause an early free. INT64_MAX/2 leaves room for retains
         * (which bump rc up) without overflowing, and is large enough that
         * a saturating release won't drive it to 0. */
        const int64_t GC_PIN_RC = (int64_t)0x4000000000000000LL;
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            __atomic_store_n(&c->obj->rc, GC_PIN_RC, __ATOMIC_RELAXED);
        }

        /* Phase 5b: Run all user deinits while every collected object is
         * still pinned and fully wired up. Deinit can freely call methods
         * on `self` and read any field. */
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            ObjHeader* h = OBJ_HEADER(c->obj);
            TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
            if (desc != NULL && desc->deinit_fn != NULL) {
                desc->deinit_fn(c->obj);
            }
        }

        /* Phase 5c: Detect resurrections. A deinit that stored `self` into
         * a live container or global will have bumped rc above the pin.
         * Such objects must NOT be freed — restore their rc to the saved
         * external-reference count and skip the teardown. */
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            int64_t cur = __atomic_load_n(&c->obj->rc, __ATOMIC_RELAXED);
            int64_t extra = cur - GC_PIN_RC;
            if (extra > 0) {
                /* Resurrected: restore observable rc to (saved + extra),
                 * leave object in gc_object_list, and skip free. */
                int64_t restored = (c->saved_rc > 0 ? c->saved_rc : 1) + extra;
                __atomic_store_n(&c->obj->rc, restored, __ATOMIC_RELAXED);
                c->collected = 0;
                collected_count--;
            }
        }

        } /* any_deinit */

        /* Phase 5d+5e (fused): for each collected object, release its
         * pointer fields and unlink it from gc_object_list in one scan, then
         * free everything in a second scan.
         *
         * Releases for ALL collected objects must complete before ANY of
         * them is freed: a closed cycle always has a back-edge to an
         * earlier-freed member, and releasing through it after the free
         * would scribble on the recycled pool slot (whose first word is the
         * free-list link). Hence release-all, then free-all.
         *
         * Unlinking inside the release scan is safe because nothing is freed
         * yet: a nested survivor teardown (a release driving a survivor's rc
         * to 0 calls rt_obj_release_slow -> gc_list_remove, which works under
         * gc_running) keeps the list consistent, and an already-unlinked
         * collected object's stale prev/next are never read again.
         * gc_old_head is NULL during a collection, so no boundary fixup. */
        if (any_deinit) {
        /* Deinit variant: collected objects are PINNED (rc ~= 2^62), so
         * "target is collected" is a simple magnitude test — survivors and
         * resurrected objects had their small exact rc restored. Null such
         * edges before the generic field release so it cannot decrement a
         * pinned rc or follow a dying edge. */
        const int64_t GC_PIN_TEST = (int64_t)1 << 61;
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            ObjHeader* h = c->obj;
            TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
            if (desc != NULL) {
                int32_t field_count = rt_get_field_count(desc);
                FieldDescriptor* fields = rt_get_field_descriptors(desc);
                if (field_count > 0 && fields != NULL) {
                    void* payload = OBJ_PAYLOAD(h);
                    int32_t enum_tag = 0;
                    int32_t tag_available = 0;
                    for (int32_t f = 0; f < field_count; f++) {
                        FieldDescriptor* fd = &fields[f];
                        if (fd->case_tag >= 0) {
                            if (!tag_available) {
                                enum_tag = *(int32_t*)payload;
                                tag_available = 1;
                            }
                            if ((int32_t)enum_tag != fd->case_tag) continue;
                        }
                        void** field_ptr = (void**)((char*)payload + fd->offset);
                        void* target = *field_ptr;
                        if (target != NULL &&
                            OBJ_HEADER(target)->rc >= GC_PIN_TEST) {
                            /* Target is also collected — null the slot
                             * so we don't decrement its pinned rc. */
                            *field_ptr = NULL;
                        }
                    }
                }
            }
            obj_release_fields(h);
            ObjHeader* p = h->prev;
            ObjHeader* n = h->next;
            if (p != NULL) p->next = n;
            else           gc_object_list = n;
            if (n != NULL) n->prev = p;
        }
        } else {
        /* Fast variant (no deinits ran): the trial refcounts are exact, so
         * every collected object's rc is exactly 0 (plus stale GC bits) and
         * a release along a collected->collected edge merely perturbs a dead
         * rc — it can never re-enter the teardown path (which fires only on
         * the 1 -> 0 transition). No nulling walk needed: release every
         * collected object's fields directly via the codegen fast path. */
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            ObjHeader* h = c->obj;
            TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
            if (desc != NULL && desc->release_fields_fn != NULL) {
                desc->release_fields_fn(OBJ_PAYLOAD(h));
            } else {
                obj_release_fields(h);
            }
            ObjHeader* p = h->prev;
            ObjHeader* n = h->next;
            if (p != NULL) p->next = n;
            else           gc_object_list = n;
            if (n != NULL) n->prev = p;
        }
        }

        /* Free scan, shared by both variants. */
        for (int32_t i = 0; i < gc_candidate_count; i++) {
            GCCandidate* c = &gc_candidates[i];
            if (!c->collected) continue;
            ObjHeader* h = c->obj;
            TypeDescriptor* desc = rt_get_type_descriptor(h->type_id);
            int64_t total = (desc != NULL) ? (OBJ_HEADER_SIZE + desc->payload_size) : 0;
            if (desc != NULL && total <= (int64_t)POOL_MAX_TOTAL_SIZE) {
                pool_free_object((void*)h, (size_t)total);
            } else {
                rt_free(h);
            }
        }
    }

    /* Adapt the next gap to the surviving live set so the next O(live) scan is
     * amortized over a proportional number of allocations, floored and capped.
     * `survivors` approximates objects still live after this pass: `live_count`
     * was the pre-pass live set and `collected_count` is how many were freed
     * (already net of any deinit resurrections from Phase 5c). We use total
     * live, not gc_candidate_count, so acyclic objects (excluded from
     * candidates) still count toward the heap size the gap is amortized
     * against — the allocation counter that drives the gap counts them too. */
    int64_t survivors = (int64_t)live_count - (int64_t)collected_count;
    /* The next minor scans only the young region and adds this to it. */
    gc_old_live_count = survivors;
    int64_t gap = survivors * GC_GROWTH;
    if (gap < GC_MIN_GAP) gap = GC_MIN_GAP;
    if (gap > GC_MAX_GAP) gap = GC_MAX_GAP;
    gc_next_gap = gap;

    gc_last_collect_count = gc_alloc_counter;
    gc_trigger_at = gc_alloc_counter + gc_next_gap;
    /* Tenure: every object now in the list (all survivors, plus any allocated
     * by deinits during this pass) becomes old. The next minor scans only what
     * is allocated after this point. */
    gc_old_head = gc_object_list;
    gc_running = 0;
    atomic_flag_clear_explicit(&gc_list_lock, memory_order_release);
}

/**
 * Get the total number of typed-object allocations since program start.
 * Used by codegen to decide when to trigger GC.
 */
int64_t rt_obj_alloc_count(void) {
    int64_t count;
    gc_list_lock_acquire();
    count = gc_alloc_counter;
    gc_list_lock_release();
    return count;
}

/**
 * Number of typed objects currently live (in the GC list). Introspection for
 * leak tests: a workload that allocates then drops N objects should leave this
 * near its steady-state baseline, not growing with N.
 */
int64_t rt_obj_live_count(void) {
    int64_t n = 0;
    gc_list_lock_acquire();
    for (ObjHeader* o = gc_object_list; o != NULL; o = o->next) {
        if (o->rc > 0) n++;
    }
    gc_list_lock_release();
    return n;
}

/**
 * Get the number of objects collected by GC (for diagnostics).
 */
int64_t rt_gc_cycle_count(void) {
    return gc_cycle_count;
}
