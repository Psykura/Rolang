// Standard library: iterator types and protocol declarations.
//
// The compiler pre-registers two builtin protocols used by for-in loops:
//
//   protocol Iterator  — any type with  def __next__() -> Element?
//   protocol Iterable  — any type with  def __iter__() -> IteratorType
//
// Concrete types implementing these two methods participate in for-in
// loops automatically via witness-table dispatch.
//
// Types shipped here:
//   Range           — half-open i32 interval [start, end)
//   CharIter        — bytes of a String as i32 ASCII codes
//   DictIter<K>     — key iterator for Dict<K, V>; obtain via dict_keys(d)

import "vec.rl"
import "dict.rl"
import "string.rl"

// ============================================================================
// Range — half-open i32 interval [current, end).
// ============================================================================

pub struct Range {
    var current: i32;
    var end: i32;

    pub static def new(end: i32) -> Range {
        return Range { current: 0, end: end };
    }

    pub static def from_to(start: i32, end: i32) -> Range {
        return Range { current: start, end: end };
    }

    pub def __iter__() -> Range {
        return self;
    }

    pub def __next__() -> i32? {
        if self.current < self.end {
            var val = self.current;
            self.current = self.current + 1;
            return val;
        }
        return nil;
    }
}

pub def range_i32(end: i32) -> Range {
    return Range.new(end);
}

pub def range_from_to(start: i32, end: i32) -> Range {
    return Range.from_to(start, end);
}

// ============================================================================
// CharIter — iterate the bytes of a String as i32 ASCII codes.
//
// This iterates BYTES, not codepoints. For pure-ASCII source this is
// fine; full UTF-8 decoding lives in a future text.rl.
// ============================================================================

pub extern "C" def rt_string_len(s: String) -> i64;
pub extern "C" def rt_string_char_at(s: String, index: i32) -> i32;

pub struct CharIter {
    var s: String;
    var pos: i32;
    var len: i32;

    pub def __iter__() -> CharIter {
        return self;
    }

    pub def __next__() -> i32? {
        if self.pos < self.len {
            unsafe {
                let ch = rt_string_char_at(self.s, self.pos);
                self.pos = self.pos + 1;
                return ch;
            }
        }
        return nil;
    }
}

pub def chars_of(s: String) -> CharIter {
    unsafe { return CharIter { s: s, pos: 0, len: rt_string_len(s) as i32 }; }
}

// ============================================================================
// DictIter<K> — key iterator for Dict<K, V>.
//
// Obtain via  `dict_keys(my_dict)`:
//
//     for k in dict_keys(my_dict) { ... }
//
// Internally uses `rt_dict_key_copy` which correctly copies both primitive
// and heap-typed keys (retaining heap references for the caller).
// ============================================================================

// Dictionary key copying is declared by dict.rl.

// Holds the `Dict<K, V>` by value (like `VecIter` holds its `Vec<T>`) so ARC
// keeps the dict alive for the whole iteration. The earlier `handle: RawPtr`
// form held no strong reference, so iterating a dict that was only transiently
// alive — e.g. `for k in dict_keys(make_dict())` — read freed memory (UAF) once
// the source dict was released. Parameterizing on V (not just K) is what lets
// the iterator store the typed `Dict<K, V>`; no caller names `DictIter` directly
// (they use `dict_keys`), so the extra type parameter is source-compatible.
pub struct DictIter<K, V> {
    var dict: Dict<K, V>;
    var index: i64;

    pub def __iter__() -> DictIter<K, V> {
        return self;
    }

    pub def __next__() -> K? {
        if self.index < self.dict.len() {
            var out: K;
            unsafe {
                rt_dict_key_copy(self.dict.raw_handle(), self.index, out as RawPtr);
                self.index = self.index + 1;
            }
            return out;
        }
        return nil;
    }
}

// Construct a key iterator for a Dict<K, V>.
// Usage:  for k in dict_keys(my_dict) { ... }
// Do not structurally mutate the dictionary during live iteration.
// Use d.keys() or d.entries() snapshots when removing entries in a loop.
pub def dict_keys<K, V>(d: Dict<K, V>) -> DictIter<K, V> {
    return DictIter<K, V> { dict: d, index: 0 };
}

// ============================================================================
// Convenience helpers (compatibility shims).
// ============================================================================

pub def vec_indices<T>(v: Vec<T>) -> Range {
    return Range { current: 0, end: v.len() };
}

pub def dict_indices<K, V>(d: Dict<K, V>) -> Range {
    return Range { current: 0, end: d.len() as i32 };
}
