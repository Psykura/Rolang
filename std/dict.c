#include "collections.h"
#include "../runtime/platform.h"
#include "dict.h"
#include "../runtime/api.h"
#include "string.h"

/* ============================================================================
 * Collections
 *
 * Dictionaries store byte copies of values via a linear-probe table.
 * ============================================================================ */

enum {
    RT_DICT_KEY_BYTES = 0,
    RT_DICT_KEY_STRING = 1
};

/*
 * Dictionary layout — compact ordered dictionary:
 *
 *   1. ``entries`` is a packed, insertion-ordered array of (key, value)
 *      pairs occupying indices [0, len). Iteration walks 0..len.
 *   2. ``buckets`` is a parallel hash table (size = power of two) mapping
 *      a bucket slot to an index into ``entries`` (-1 = empty). Lookup
 *      and update use linear probing over this table.
 *
 * The single backing allocation lays out:
 *      [RolangDict header]
 *      [entries data ... capacity * (key_size + value_size)]
 *      [buckets   ... bucket_count * sizeof(int32_t)]
 *
 * Grow policy: keep buckets_count = next_pow2(capacity * 2). When the
 * load factor on buckets exceeds 0.75, both entries and buckets are
 * reallocated and re-indexed.
 *
 * ``key_type_id`` / ``value_type_id`` are type-descriptor indices:
 *   0 = primitive (no retain/release needed)
 *   non-zero = heap type (retain on insert, release on overwrite/free)
 *
 * Removal repairs the probe chain and compacts the entries; surviving
 * entries retain insertion order without tombstones.
 */
typedef struct RolangDict {
    int64_t len;
    int64_t capacity;          /* entries array size */
    int64_t key_size;
    int64_t value_size;
    int32_t key_kind;
    int32_t key_type_id;
    int32_t value_type_id;
    int32_t bucket_count;      /* must be a power of two; -1 in empty hashes */
    int64_t buckets_offset;    /* byte offset from data[] to buckets[] */
    unsigned char data[];      /* entries followed by buckets */
} RolangDict;

#define RT_DICT_BUCKET_EMPTY (-1)

/* Bucket slot: entry index + 32-bit hash tag. The tag is the HIGH half of the
 * 64-bit key hash (the bucket position uses the low bits, so the two are
 * decorrelated). Probing compares tags first and only dereferences/compares
 * the actual keys on a tag match, which removes nearly every key memcmp from
 * the probe loop — the dominant cost in string-keyed hot loops (word_freq). */
typedef struct {
    int32_t  idx;   /* index into entries[], or RT_DICT_BUCKET_EMPTY */
    uint32_t tag;   /* high 32 bits of the key hash; undefined when empty */
} DictBucket;

static inline size_t _dict_stride(const RolangDict* dict) {
    return (size_t)dict->key_size + (size_t)dict->value_size;
}

static unsigned char* rt_dict_key_at(RolangDict* dict, int64_t index) {
    return dict->data + ((size_t)index * _dict_stride(dict));
}

static unsigned char* rt_dict_value_at(RolangDict* dict, int64_t index) {
    return rt_dict_key_at(dict, index) + (size_t)dict->key_size;
}

static DictBucket* _dict_buckets(RolangDict* dict) {
    return (DictBucket*)(dict->data + (size_t)dict->buckets_offset);
}

/* Byte equality without the memcmp libcall for short runs. Keys in hash-table
 * hot loops are typically a handful of bytes; the call overhead of memcmp
 * dwarfs the comparison itself. Overlapping word loads cover 4..16 bytes in
 * two compares; memcpy compiles to plain loads at -O1+. */
static inline int _dict_bytes_equal(const unsigned char* a,
                                    const unsigned char* b, size_t n) {
    if (n >= 16) {
        return memcmp(a, b, n) == 0;
    }
    if (n >= 8) {
        uint64_t x0, y0, x1, y1;
        memcpy(&x0, a, 8);
        memcpy(&y0, b, 8);
        memcpy(&x1, a + n - 8, 8);
        memcpy(&y1, b + n - 8, 8);
        return ((x0 ^ y0) | (x1 ^ y1)) == 0;
    }
    if (n >= 4) {
        uint32_t x0, y0, x1, y1;
        memcpy(&x0, a, 4);
        memcpy(&y0, b, 4);
        memcpy(&x1, a + n - 4, 4);
        memcpy(&y1, b + n - 4, 4);
        return ((x0 ^ y0) | (x1 ^ y1)) == 0;
    }
    for (size_t i = 0; i < n; i++) {
        if (a[i] != b[i]) return 0;
    }
    return 1;
}

__attribute__((always_inline))
static inline int rt_dict_keys_equal(RolangDict* dict, const void* lhs, const void* rhs) {
    if (dict->key_kind == RT_DICT_KEY_STRING) {
        StringVal a_val;
        StringVal b_val;
        if (dict->key_type_id != 0) {
            a_val = rt_string_obj_value(*(void* const*)lhs);
            b_val = rt_string_obj_value(*(void* const*)rhs);
        } else {
            a_val = *(const StringVal*)lhs;
            b_val = *(const StringVal*)rhs;
        }
        const StringVal* a = &a_val;
        const StringVal* b = &b_val;

        if (a->len != b->len) {
            return 0;
        }
        if (a->len == 0) {
            return 1;
        }
        if (a->data == NULL || b->data == NULL) {
            return a->data == b->data;
        }
        return _dict_bytes_equal((const unsigned char*)a->data,
                                 (const unsigned char*)b->data, (size_t)a->len);
    }

    return _dict_bytes_equal((const unsigned char*)lhs,
                             (const unsigned char*)rhs, (size_t)dict->key_size);
}

/* Word-at-a-time multiply-xor hash.
 * Replaces byte-at-a-time FNV-1a: same interface, ~8x fewer multiplies on
 * long keys and a single data multiply for the <=8-byte keys that dominate
 * dict-as-counter workloads. The multiply pushes entropy into the HIGH bits;
 * the closing `h ^= h >> 32` folds those well-mixed bits back into the low
 * bits that feed the pow2 bucket mask. The tag (high 32 bits) is mixed by
 * the multiply alone. Kept deliberately short: hash latency sits on the
 * critical path of every dict lookup, and a full splitmix finalizer costs
 * more than it buys at hash-table quality levels. */
static inline uint64_t _dict_hash_bytes(const unsigned char* p, size_t n) {
    const uint64_t K = 0x9e3779b97f4a7c15ULL;
    uint64_t h = 0xcbf29ce484222325ULL ^ ((uint64_t)n * K);
    if (n > 8) {
        do {
            uint64_t w;
            memcpy(&w, p, 8);
            h = (h ^ w) * K;
            p += 8;
            n -= 8;
        } while (n >= 8);
        if (n > 0) {
            /* Overlapping tail load: total length > 8, so p+n-8 is valid. */
            uint64_t w;
            memcpy(&w, p + n - 8, 8);
            h = (h ^ w) * K;
        }
    } else if (n > 0) {
        uint64_t w;
        if (n == 8) {
            memcpy(&w, p, 8);
        } else if (n >= 4) {
            /* Two overlapping 4-byte loads cover 4..7 bytes. */
            uint32_t lo, hi;
            memcpy(&lo, p, 4);
            memcpy(&hi, p + n - 4, 4);
            w = (uint64_t)lo | ((uint64_t)hi << 32);
        } else {
            /* 1..3 bytes: independent loads, no carried dependency. */
            w = (uint64_t)p[0]
              | ((uint64_t)p[n >> 1] << 8)
              | ((uint64_t)p[n - 1] << 16);
        }
        h = (h ^ w) * K;
    }
    h ^= h >> 32;
    return h;
}

__attribute__((always_inline))
static inline uint64_t _dict_hash_key(RolangDict* dict, const void* key) {
    if (dict->key_kind == RT_DICT_KEY_STRING) {
        if (dict->key_type_id != 0) {
            /* Heap String object: memoize the hash in the object itself.
             * Hot dict workloads look the same few key objects up millions
             * of times (e.g. a pre-built key vector); after the first probe
             * the hash is a single load instead of a recompute. 0 means
             * "not computed" — a computed hash is forced non-zero. */
            void* obj = *(void* const*)key;
            StringPayload* sp = rt_string_payload(obj);
            if (sp == NULL) {
                return _dict_hash_bytes(NULL, 0);
            }
            uint64_t cached = (uint64_t)sp->hash;
            if (cached != 0) {
                return cached;
            }
            uint64_t h = (sp->data == NULL || sp->len <= 0)
                ? _dict_hash_bytes(NULL, 0)
                : _dict_hash_bytes((const unsigned char*)sp->data, (size_t)sp->len);
            if (h == 0) h = 0x9e3779b97f4a7c15ULL;
            sp->hash = (int64_t)h;
            return h;
        }
        StringVal s_val = *(const StringVal*)key;
        if (s_val.data == NULL || s_val.len <= 0) {
            return _dict_hash_bytes(NULL, 0);
        }
        return _dict_hash_bytes((const unsigned char*)s_val.data, (size_t)s_val.len);
    }
    return _dict_hash_bytes((const unsigned char*)key, (size_t)dict->key_size);
}

static int64_t _next_pow2_at_least(int64_t v) {
    if (v < 1) return 1;
    int64_t out = 1;
    while (out < v) out *= 2;
    return out;
}

/* ---- retain / release helpers for dict keys and values ---- */

static inline void _dict_retain_element(int32_t type_id, const void* ptr) {
    if (type_id == 0 || ptr == NULL) return;
    void* obj = *(void**)ptr;
    if (obj != NULL) rt_obj_retain(obj);
}

static inline void _dict_release_element(int32_t type_id, void* ptr) {
    if (type_id == 0 || ptr == NULL) return;
    void* obj = *(void**)ptr;
    if (obj != NULL) rt_obj_release(obj);
}

static void _dict_release_all(RolangDict* dict) {
    if (dict->key_type_id != 0 || dict->value_type_id != 0) {
        for (int64_t i = 0; i < dict->len; i++) {
            _dict_release_element(dict->key_type_id, rt_dict_key_at(dict, i));
            _dict_release_element(dict->value_type_id, rt_dict_value_at(dict, i));
        }
    }
}

static size_t _dict_alloc_size(int64_t capacity, int64_t key_size, int64_t value_size,
                                int64_t bucket_count) {
    size_t entries = (size_t)capacity * ((size_t)key_size + (size_t)value_size);
    /* Align bucket table to 4 bytes (DictBucket is two 4-byte fields). */
    entries = (entries + 3u) & ~(size_t)3u;
    return sizeof(RolangDict) + entries + (size_t)bucket_count * sizeof(DictBucket);
}

static void _dict_clear_buckets(RolangDict* dict) {
    if (dict->bucket_count <= 0) return;
    DictBucket* buckets = _dict_buckets(dict);
    for (int64_t i = 0; i < dict->bucket_count; i++) {
        buckets[i].idx = RT_DICT_BUCKET_EMPTY;
        buckets[i].tag = 0;
    }
}

/* Rebuild buckets[] from the entries array. */
static void _dict_rehash(RolangDict* dict) {
    _dict_clear_buckets(dict);
    if (dict->bucket_count <= 0) return;
    DictBucket* buckets = _dict_buckets(dict);
    uint64_t mask = (uint64_t)(dict->bucket_count - 1);
    for (int64_t i = 0; i < dict->len; i++) {
        uint64_t hash = _dict_hash_key(dict, rt_dict_key_at(dict, i));
        uint64_t h = hash & mask;
        while (buckets[h].idx != RT_DICT_BUCKET_EMPTY) {
            h = (h + 1) & mask;
        }
        buckets[h].idx = (int32_t)i;
        buckets[h].tag = (uint32_t)(hash >> 32);
    }
}

/* ---- public API ---- */

void* rt_dict_new(int64_t capacity, int64_t key_size, int64_t value_size,
                  int32_t key_kind, int32_t key_type_id, int32_t value_type_id) {
    if (capacity < 0 || key_size < 0 || value_size < 0) {
        return NULL;
    }

    if (capacity < 8) capacity = 8;
    int64_t bucket_count = _next_pow2_at_least(capacity * 4);

    size_t total = _dict_alloc_size(capacity, key_size, value_size, bucket_count);
    RolangDict* dict = (RolangDict*)malloc(total);
    if (dict == NULL) {
        return NULL;
    }

    dict->len = 0;
    dict->capacity = capacity;
    dict->key_size = key_size;
    dict->value_size = value_size;
    dict->key_kind = key_kind;
    dict->key_type_id = key_type_id;
    dict->value_type_id = value_type_id;
    dict->bucket_count = (int32_t)bucket_count;

    size_t entries_bytes = (size_t)capacity * ((size_t)key_size + (size_t)value_size);
    size_t entries_aligned = (entries_bytes + 3u) & ~(size_t)3u;
    dict->buckets_offset = (int64_t)entries_aligned;
    if (entries_bytes > 0) {
        memset(dict->data, 0, entries_bytes);
    }
    _dict_clear_buckets(dict);

    return dict;
}

void* rt_dict_resize(void* dict_ptr, int64_t new_capacity) {
    if (!dict_ptr || new_capacity <= 0) return dict_ptr;
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (new_capacity <= dict->capacity) return dict_ptr;

    int64_t new_bucket_count = _next_pow2_at_least(new_capacity * 4);
    size_t total = _dict_alloc_size(new_capacity, dict->key_size, dict->value_size,
                                    new_bucket_count);
    RolangDict* new_dict = (RolangDict*)malloc(total);
    if (!new_dict) return dict_ptr;

    *new_dict = *dict;  /* copy header (will fix offsets below) */
    new_dict->capacity = new_capacity;
    new_dict->bucket_count = (int32_t)new_bucket_count;
    size_t entries_bytes = (size_t)new_capacity *
        ((size_t)new_dict->key_size + (size_t)new_dict->value_size);
    size_t entries_aligned = (entries_bytes + 3u) & ~(size_t)3u;
    new_dict->buckets_offset = (int64_t)entries_aligned;

    if (dict->len > 0) {
        memcpy(new_dict->data, dict->data,
               (size_t)dict->len * _dict_stride(dict));
    }
    if (entries_bytes > (size_t)dict->len * _dict_stride(dict)) {
        memset(new_dict->data + (size_t)dict->len * _dict_stride(dict), 0,
               entries_bytes - (size_t)dict->len * _dict_stride(dict));
    }

    _dict_rehash(new_dict);
    /* No retain/release here — entries are byte-copied, including the
     * embedded pointers; their refcounts stay correct. */
    free(dict);
    return new_dict;
}

/* Look up an entry index for ``key`` and return -1 on miss.
 * On hit, ``*out_bucket`` is the bucket slot that holds the index;
 * on miss, ``*out_bucket`` is the slot where a fresh entry should land.
 * ``*out_tag`` is always set to the key's bucket tag so insert paths can
 * record it without rehashing. */
__attribute__((always_inline))
static inline int32_t _dict_probe(RolangDict* dict, const void* key,
                                  uint64_t* out_bucket, uint32_t* out_tag) {
    DictBucket* buckets = _dict_buckets(dict);
    uint64_t mask = (uint64_t)(dict->bucket_count - 1);
    uint64_t hash = _dict_hash_key(dict, key);
    uint32_t tag = (uint32_t)(hash >> 32);
    uint64_t h = hash & mask;
    *out_tag = tag;
    for (;;) {
        DictBucket b = buckets[h];
        if (b.idx == RT_DICT_BUCKET_EMPTY) {
            *out_bucket = h;
            return -1;
        }
        if (b.tag == tag) {
            unsigned char* existing_key = rt_dict_key_at(dict, b.idx);
            if (rt_dict_keys_equal(dict, existing_key, key)) {
                *out_bucket = h;
                return b.idx;
            }
        }
        h = (h + 1) & mask;
    }
}

void* rt_dict_set(void* dict_ptr, const void* key, const void* value) {
    if (dict_ptr == NULL || key == NULL || value == NULL) {
        return dict_ptr;
    }

    RolangDict* dict = (RolangDict*)dict_ptr;
    uint64_t bucket;
    uint32_t tag;
    int32_t idx = _dict_probe(dict, key, &bucket, &tag);
    if (idx >= 0) {
        /* Update existing value: release old, copy new, retain new. */
        unsigned char* slot = rt_dict_value_at(dict, idx);
        _dict_release_element(dict->value_type_id, slot);
        memcpy(slot, value, (size_t)dict->value_size);
        _dict_retain_element(dict->value_type_id, slot);
        return dict_ptr;
    }

    /* Grow when entries or buckets are too tight. */
    int needs_grow = (dict->len + 1) >= dict->capacity
        || (dict->len + 1) * 4 > (int64_t)dict->bucket_count * 3;
    if (needs_grow) {
        int64_t new_cap = dict->capacity * 2;
        if (new_cap < 16) new_cap = 16;
        void* new_ptr = rt_dict_resize(dict_ptr, new_cap);
        if (new_ptr == dict_ptr) {
            return dict_ptr;  /* Resize failed; bail out. */
        }
        dict = (RolangDict*)new_ptr;
        dict_ptr = new_ptr;
        idx = _dict_probe(dict, key, &bucket, &tag);
        if (idx >= 0) {
            unsigned char* slot = rt_dict_value_at(dict, idx);
            _dict_release_element(dict->value_type_id, slot);
            memcpy(slot, value, (size_t)dict->value_size);
            _dict_retain_element(dict->value_type_id, slot);
            return dict_ptr;
        }
    }

    /* Append new entry and record it in the bucket. */
    int64_t new_idx = dict->len;
    unsigned char* dest_key = rt_dict_key_at(dict, new_idx);
    unsigned char* dest_value = rt_dict_value_at(dict, new_idx);
    memcpy(dest_key, key, (size_t)dict->key_size);
    memcpy(dest_value, value, (size_t)dict->value_size);
    _dict_retain_element(dict->key_type_id, dest_key);
    _dict_retain_element(dict->value_type_id, dest_value);

    DictBucket* buckets = _dict_buckets(dict);
    buckets[bucket].idx = (int32_t)new_idx;
    buckets[bucket].tag = tag;
    dict->len++;
    return dict_ptr;
}

int32_t rt_dict_get(void* dict_ptr, const void* key, void* out) {
    if (dict_ptr == NULL || key == NULL || out == NULL) {
        return 0;
    }

    RolangDict* dict = (RolangDict*)dict_ptr;
    if (dict->len == 0) {
        memset(out, 0, (size_t)dict->value_size);
        return 0;
    }
    uint64_t bucket;
    uint32_t tag;
    int32_t idx = _dict_probe(dict, key, &bucket, &tag);
    if (idx >= 0) {
        _rt_copy_small(out, rt_dict_value_at(dict, idx), (size_t)dict->value_size);
        /* Retain heap-typed values for the caller. Without this the dict
         * still owns the slot but the caller's `out` would drop without
         * having been retained, causing a UAF the next time the dict is
         * read or destroyed. */
        _dict_retain_element(dict->value_type_id, out);
        return 1;
    }
    memset(out, 0, (size_t)dict->value_size);
    return 0;
}

/* Probe-or-insert in a SINGLE hash+probe: ensure `key` is present (inserting a
 * copy of *default_value if absent — a NULL default zero-fills) and write the
 * entry's array index to *out_index (an int64_t). Returns the (possibly resized)
 * dict pointer. Pair with rt_dict_get_at / rt_dict_set_at, whose index access is
 * O(1) and hash-free, so a read-modify-write (e.g. dict-as-counter: read count,
 * write count+1) pays ONE probe instead of the two that get()+set() cost. Entry
 * indices are stable: entries are append-only and resize preserves their order
 * (the dict has no remove), so an index stays valid until the next mutation. */
void* rt_dict_entry_index(void* dict_ptr, const void* key,
                          const void* default_value, void* out_index) {
    if (out_index == NULL) {
        return dict_ptr;
    }
    if (dict_ptr == NULL || key == NULL) {
        *(int64_t*)out_index = -1;
        return dict_ptr;
    }

    RolangDict* dict = (RolangDict*)dict_ptr;
    uint64_t bucket;
    uint32_t tag;
    int32_t idx = _dict_probe(dict, key, &bucket, &tag);
    if (idx >= 0) {
        *(int64_t*)out_index = idx;
        return dict_ptr;
    }

    /* Absent: grow if tight, then append (mirrors rt_dict_set's insert path). */
    int needs_grow = (dict->len + 1) >= dict->capacity
        || (dict->len + 1) * 4 > (int64_t)dict->bucket_count * 3;
    if (needs_grow) {
        int64_t new_cap = dict->capacity * 2;
        if (new_cap < 16) new_cap = 16;
        void* new_ptr = rt_dict_resize(dict_ptr, new_cap);
        if (new_ptr == dict_ptr) {
            *(int64_t*)out_index = -1;  /* resize failed */
            return dict_ptr;
        }
        dict = (RolangDict*)new_ptr;
        dict_ptr = new_ptr;
        idx = _dict_probe(dict, key, &bucket, &tag);
        if (idx >= 0) {
            *(int64_t*)out_index = idx;  /* defensive; was absent pre-resize */
            return dict_ptr;
        }
    }

    int64_t new_idx = dict->len;
    unsigned char* dest_key = rt_dict_key_at(dict, new_idx);
    unsigned char* dest_value = rt_dict_value_at(dict, new_idx);
    memcpy(dest_key, key, (size_t)dict->key_size);
    if (default_value != NULL) {
        memcpy(dest_value, default_value, (size_t)dict->value_size);
    } else {
        memset(dest_value, 0, (size_t)dict->value_size);
    }
    _dict_retain_element(dict->key_type_id, dest_key);
    _dict_retain_element(dict->value_type_id, dest_value);

    DictBucket* buckets = _dict_buckets(dict);
    buckets[bucket].idx = (int32_t)new_idx;
    buckets[bucket].tag = tag;
    dict->len++;
    *(int64_t*)out_index = new_idx;
    return dict_ptr;
}

/* O(1) value read by entry index (no hash/probe). Retains heap-typed values for
 * the caller, exactly like rt_dict_get. `index` must come from rt_dict_entry_index
 * (or a dict iteration) and be valid for the current dict. */
void rt_dict_get_at(void* dict_ptr, int64_t index, void* out) {
    if (dict_ptr == NULL || out == NULL) {
        return;
    }
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (index < 0 || index >= dict->len) {
        memset(out, 0, (size_t)dict->value_size);
        return;
    }
    _rt_copy_small(out, rt_dict_value_at(dict, index), (size_t)dict->value_size);
    _dict_retain_element(dict->value_type_id, out);
}

/* O(1) value write by entry index (no hash/probe). Releases the old value and
 * retains the new, exactly like rt_dict_set's update path. */
void rt_dict_set_at(void* dict_ptr, int64_t index, const void* value) {
    if (dict_ptr == NULL || value == NULL) {
        return;
    }
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (index < 0 || index >= dict->len) {
        return;
    }
    unsigned char* slot = rt_dict_value_at(dict, index);
    _dict_release_element(dict->value_type_id, slot);
    _rt_copy_small(slot, value, (size_t)dict->value_size);
    _dict_retain_element(dict->value_type_id, slot);
}

/* Remove with backward-shift bucket repair and ordered entry compaction.
 * O(n + capacity); preserves insertion order but invalidates entry indices.
 * The removed value's ownership transfers to out. */
int32_t rt_dict_remove(void* ptr, const void* key, void* out) {
    if (!ptr || !key || !out) return 0;
    RolangDict* dict = ptr;
    uint64_t hole; uint32_t tag;
    int32_t idx = _dict_probe(dict, key, &hole, &tag);
    if (idx < 0) return 0;
    void* old_key = dict->key_type_id ? *(void**)rt_dict_key_at(dict, idx) : NULL;
    memcpy(out, rt_dict_value_at(dict, idx), (size_t)dict->value_size);
    DictBucket* buckets = _dict_buckets(dict);
    uint64_t mask = (uint64_t)dict->bucket_count - 1;
    uint64_t scan = (hole + 1) & mask;
    while (buckets[scan].idx != RT_DICT_BUCKET_EMPTY) {
        uint64_t ideal = _dict_hash_key(dict, rt_dict_key_at(dict, buckets[scan].idx)) & mask;
        if (((hole - ideal) & mask) < ((scan - ideal) & mask)) {
            buckets[hole] = buckets[scan]; hole = scan;
        }
        scan = (scan + 1) & mask;
    }
    buckets[hole].idx = RT_DICT_BUCKET_EMPTY; buckets[hole].tag = 0;
    int64_t last = dict->len - 1;
    if (idx != last) {
        memmove(rt_dict_key_at(dict, idx), rt_dict_key_at(dict, idx + 1),
                (size_t)(last - idx) * _dict_stride(dict));
        for (int32_t i = 0; i < dict->bucket_count; i++)
            if (buckets[i].idx > idx) buckets[i].idx--;
    }
    dict->len--;
    memset(rt_dict_key_at(dict, last), 0, _dict_stride(dict));
    if (old_key) rt_obj_release(old_key);
    return 1;
}
void rt_dict_clear(void* ptr) {
    if (!ptr) return;
    RolangDict* dict = ptr;
    _dict_release_all(dict);
    dict->len = 0;
    _dict_clear_buckets(dict);
}

int64_t rt_dict_len(void* dict_ptr) {
    if (dict_ptr == NULL) {
        return 0;
    }

    RolangDict* dict = (RolangDict*)dict_ptr;
    return dict->len;
}

void* rt_dict_key_ptr(void* dict_ptr, int64_t index) {
    if (!dict_ptr || index < 0) return NULL;
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (index >= dict->len) return NULL;
    return rt_dict_key_at(dict, index);
}

/* Copy the key at `index` into `out`, retaining heap-typed keys.
 * Mirrors rt_gvec_get: the caller receives a fresh strong reference for
 * heap keys, and raw bytes for primitive keys. Safe for DictIter.__next__. */
void rt_dict_key_copy(void* dict_ptr, int64_t index, void* out) {
    if (!dict_ptr || !out) return;
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (index < 0 || index >= dict->len) return;
    unsigned char* src = rt_dict_key_at(dict, index);
    memcpy(out, src, (size_t)dict->key_size);
    _dict_retain_element(dict->key_type_id, out);
}

/* Pointer to the value slot at `index` (0 <= index < rt_dict_len).
 * Used by Dict iteration in std/iter.rl. Mirrors rt_dict_key_ptr. */
void* rt_dict_value_ptr(void* dict_ptr, int64_t index) {
    if (!dict_ptr || index < 0) return NULL;
    RolangDict* dict = (RolangDict*)dict_ptr;
    if (index >= dict->len) return NULL;
    return rt_dict_value_at(dict, index);
}

void rt_dict_free(void* dict_ptr) {
    if (!dict_ptr) return;
    RolangDict* dict = (RolangDict*)dict_ptr;
    _dict_release_all(dict);
    free(dict_ptr);
}

/*
 * GC trace hook for ``Dict<K, V>``. Mirrors :func:`rt_gvec_gc_trace`:
 * codegen installs this on every monomorphized ``Dict_*`` type's
 * ``TypeDescriptor.trace_fn``. The payload's first 8 bytes are the
 * ``handle: RawPtr`` that points at a :type:`RolangDict`.
 *
 * Heap-typed keys and values are stored interleaved in the dict's
 * ``data[]`` buffer; ``key_type_id`` / ``value_type_id`` are non-zero
 * when the corresponding slot needs to be traced (matching the
 * retain/release convention used elsewhere in this file).
 */
void rt_dict_gc_trace(void* payload, GCTraceCb cb, void* ctx) {
    if (payload == NULL || cb == NULL) return;
    void* handle = *(void**)payload;
    if (handle == NULL) return;

    RolangDict* d = (RolangDict*)handle;
    if (d->key_type_id == 0 && d->value_type_id == 0) return;

    for (int64_t i = 0; i < d->len; i++) {
        if (d->key_type_id != 0) {
            void* key_obj = *(void**)rt_dict_key_at(d, i);
            if (key_obj != NULL) cb(key_obj, ctx);
        }
        if (d->value_type_id != 0) {
            void* value_obj = *(void**)rt_dict_value_at(d, i);
            if (value_obj != NULL) cb(value_obj, ctx);
        }
    }
}
