// Standard library: generic key-value map Dict<K, V>
//
// Backed by C runtime linear-probe dict. Works for any fixed-size key
// and value types:
//
//   - String keys use key_kind=1 (content comparison via memcmp).
//   - All other keys (i32, i64, structs, ...) use key_kind=0 (bytes).
//
// Heap-typed keys and values (struct, enum, tuple) are automatically
// retained on insert and released on overwrite/free.

import "string.rl"
import "vec.rl"

pub extern "C" def rt_dict_new(capacity: i64, key_size: i64, value_size: i64,
                               key_kind: i32, key_type_id: i32, value_type_id: i32) -> RawPtr;
pub extern "C" def rt_dict_set(dict: RawPtr, key: RawPtr, value: RawPtr) -> RawPtr;
pub extern "C" def rt_dict_get(dict: RawPtr, key: RawPtr, out: RawPtr) -> i32;
pub extern "C" def rt_dict_len(dict: RawPtr) -> i64;
pub extern "C" def rt_dict_free(dict: RawPtr) -> Void;
// Single-probe read-modify-write support (see Dict.entry_index).
pub extern "C" def rt_dict_entry_index(dict: RawPtr, key: RawPtr, default: RawPtr, out_index: RawPtr) -> RawPtr;
pub extern "C" def rt_dict_get_at(dict: RawPtr, index: i64, out: RawPtr) -> Void;
pub extern "C" def rt_dict_set_at(dict: RawPtr, index: i64, value: RawPtr) -> Void;

// GC cycle-collector trace hook. Mirrors `rt_gvec_gc_trace` — iterates
// the dict's entry buffer and reports heap-typed key/value slots back
// to the GC.
pub extern "C" def rt_dict_gc_trace(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void;

pub extern "C" def rt_dict_remove(dict: RawPtr, key: RawPtr, out: RawPtr) -> i32;
pub extern "C" def rt_dict_clear(dict: RawPtr) -> Void;
pub extern "C" def rt_dict_key_copy(dict: RawPtr, index: i64, out: RawPtr) -> Void;

pub struct DictEntry<K, V> {
    pub let key: K;
    pub let value: V;
}

pub enum DictKeyKind {
    case BYTES
    case STRING
}

pub struct Dict<K, V> {
    var handle: RawPtr;

    pub static def new(capacity: i32, key_kind: i32, key_type_id: i32, value_type_id: i32) -> Dict<K, V> {
        return dict_new(capacity, size_of(K), size_of(V), key_kind, type_id(K), type_id(V));
    }

    pub static def with_capacity(capacity: i32, key_kind: i32) -> Dict<K, V> {
        return dict_new(capacity, size_of(K), size_of(V), key_kind, type_id(K), type_id(V));
    }

    // Release hook (see `Vec.__release__`).
    pub def __release__() -> Void {
        unsafe { rt_dict_free(self.handle); }
    }

    // GC trace hook (see `Vec.__gc_trace__`).
    pub static def __gc_trace__(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void {
        unsafe { rt_dict_gc_trace(payload, cb, ctx); }
    }

    pub def set(key: K, value: V) -> Void {
        unsafe {
            self.handle = rt_dict_set(self.handle, key as RawPtr, value as RawPtr);
        }
    }

    // Returns the value if the key is present, or nil otherwise.
    pub def get(key: K) -> V? {
        var out: V;
        unsafe {
            let found = rt_dict_get(self.handle, key as RawPtr, out as RawPtr);
            if found != 0 {
                return out;
            }
        }
        return nil;
    }

    pub def len() -> i64 {
        unsafe { return rt_dict_len(self.handle); }
    }

    // Single-probe read-modify-write. Ensure `key` is present (inserting
    // `default` if absent) and return its stable entry index in ONE hash+probe.
    // Pair with `value_at`/`set_value_at` (both O(1), hash-free) so a counter-
    // style update reads then writes the slot for the cost of a single probe,
    // not the two that `get` + `set` would pay:
    //
    //     let i = counts.entry_index(key, 0);
    //     counts.set_value_at(i, counts.value_at(i) + 1);
    //
    // Treat the index as invalid after any dictionary mutation.
    pub def entry_index(key: K, default: V) -> i64 {
        var idx: i64 = 0;
        unsafe {
            self.handle = rt_dict_entry_index(self.handle, key as RawPtr, default as RawPtr, idx as RawPtr);
        }
        return idx;
    }

    // O(1) value read by entry index (no hashing). Index from `entry_index`.
    pub def value_at(index: i64) -> V {
        var out: V;
        unsafe { rt_dict_get_at(self.handle, index, out as RawPtr); }
        return out;
    }

    // O(1) value write by entry index (no hashing).
    pub def set_value_at(index: i64, value: V) -> Void {
        unsafe { rt_dict_set_at(self.handle, index, value as RawPtr); }
    }

    pub def contains(key: K) -> Bool {
        var out: V;
        unsafe { return rt_dict_get(self.handle, key as RawPtr, out as RawPtr) != 0; }
    }

    // Removes a binding, transferring its value to the caller.
    // Preserves insertion order; invalidates entry indices. O(n + capacity).
    pub def remove(key: K) -> V? {
        var out: V;
        unsafe {
            if rt_dict_remove(self.handle, key as RawPtr, out as RawPtr) != 0 {
                return out;
            }
        }
        return nil;
    }

    pub def clear() -> Void { unsafe { rt_dict_clear(self.handle); } }

    // Snapshots remain valid when the dictionary is subsequently mutated.
    // Referenced key/value objects are shared, not deeply copied.
    pub def keys() -> Vec<K> {
        let result = Vec<K>.new();
        var i: i64 = 0;
        while i < self.len() {
            var key: K;
            unsafe { rt_dict_key_copy(self.handle, i, key as RawPtr); }
            result.push(key);
            i = i + 1;
        }
        return result;
    }

    pub def values() -> Vec<V> {
        let result = Vec<V>.new();
        var i: i64 = 0;
        while i < self.len() {
            result.push(self.value_at(i));
            i = i + 1;
        }
        return result;
    }

    pub def entries() -> Vec<DictEntry<K, V>> {
        let result = Vec<DictEntry<K, V>>.new();
        var i: i64 = 0;
        while i < self.len() {
            var key: K;
            unsafe { rt_dict_key_copy(self.handle, i, key as RawPtr); }
            result.push(DictEntry<K, V> { key: key, value: self.value_at(i) });
            i = i + 1;
        }
        return result;
    }

    pub def free() -> Void {
        unsafe {
            rt_dict_free(self.handle);
            self.handle = 0 as RawPtr;
        }
    }

    // Exposes the underlying runtime dictionary handle for low-level FFI
    // helpers such as key iteration. Marked unsafe because callers can break
    // ownership and layout invariants if they pass it to the wrong runtime API.
    pub unsafe def raw_handle() -> RawPtr {
        return self.handle;
    }
}

// Generic constructor. Pass key_kind=1 for String keys, 0 otherwise.
// key_type_id and value_type_id: 0 for primitives, type descriptor id
// for heap types.
pub def dict_new<K, V>(capacity: i32, key_size: i32, value_size: i32,
                       key_kind: i32, key_type_id: i32, value_type_id: i32) -> Dict<K, V> {
    var result: Dict<K, V>;
    unsafe {
        result.handle = rt_dict_new(capacity as i64, key_size as i64, value_size as i64,
                                    key_kind, key_type_id, value_type_id);
    }
    return result;
}

// ---- Convenience constructors for common types ----

pub def dict_i32_i32_new() -> Dict<i32, i32> {
    return Dict<i32, i32>.with_capacity(16, 0);
}

pub def dict_i32_i64_new() -> Dict<i32, i64> {
    return Dict<i32, i64>.with_capacity(16, 0);
}

pub def dict_string_i32_new() -> Dict<String, i32> {
    return Dict<String, i32>.with_capacity(16, 1);
}

pub def dict_string_i64_new() -> Dict<String, i64> {
    return Dict<String, i64>.with_capacity(16, 1);
}
