import "range.rl"
// Standard library: generic dynamic vector Vec<T>
//
// Backed by C runtime gvec functions. Works for any type T:
//
//   - Primitive types (i32, i64, f32, f64, Bool) are stored by value.
//   - Heap types (struct, enum, tuple) are stored as pointers with
//     automatic retain/release on push/set/pop/free.
//
// Create vectors with `Vec<T>.new()`, `Vec<T>.with_capacity(n)` or a literal.

pub extern "C" def rt_gvec_new(capacity: i32, elem_size: i32, elem_type_id: i32) -> RawPtr;
pub extern "C" def rt_gvec_len(vec: RawPtr) -> i32;
pub extern "C" def rt_gvec_get(vec: RawPtr, index: i32, out: RawPtr) -> Void;
pub extern "C" def rt_gvec_set(vec: RawPtr, index: i32, value: RawPtr) -> Void;
pub extern "C" def rt_gvec_push(vec: RawPtr, value: RawPtr) -> RawPtr;
pub extern "C" def rt_gvec_pop(vec: RawPtr, out: RawPtr) -> Void;
pub extern "C" def rt_gvec_resize(vec: RawPtr, new_capacity: i32) -> RawPtr;
pub extern "C" def rt_gvec_free(vec: RawPtr) -> Void;

// GC cycle-collector trace hook. The Rolang-side trampoline below
// (`__gc_trace__`) just forwards to this C helper; the helper walks
// the backing buffer's heap-typed slots and calls back into the GC
// for each managed pointer.
pub extern "C" def rt_gvec_gc_trace(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void;

pub struct Vec<T> {
    var handle: RawPtr;
    var elem_size: i32;

    pub static def new() -> Vec<T> {
        return Vec<T>.with_capacity(8);
    }

    pub static def with_capacity(capacity: i32) -> Vec<T> {
        return vec_new(capacity, size_of(T), type_id(T));
    }

    // Release hook: the runtime calls this on the
    // final reference-count decrement (and during GC sweeps).
    pub def __release__() -> Void {
        unsafe { rt_gvec_free(self.handle); }
    }

    // GC trace hook: tells the cycle collector how
    // to walk managed pointers held inside the backing buffer (which
    // is reached via `self.handle: RawPtr` and therefore invisible to
    // the static FieldDescriptor list).
    pub static def __gc_trace__(payload: RawPtr, cb: RawPtr, ctx: RawPtr) -> Void {
        unsafe { rt_gvec_gc_trace(payload, cb, ctx); }
    }

    pub def push(value: T) -> Void {
        unsafe { self.handle = rt_gvec_push(self.handle, value as RawPtr); }
    }

    pub def get(index: i32) -> T {
        var out: T;
        unsafe { rt_gvec_get(self.handle, index, out as RawPtr); }
        return out;
    }

    pub def set(index: i32, value: T) -> Void {
        unsafe { rt_gvec_set(self.handle, index, value as RawPtr); }
    }

    // Slicing returns an independent vector retaining the selected elements.
    pub def slice(bounds: IndexRange) -> Vec<T> {
        let out = Vec<T>.new();
        var i = bounds.lower(self.len());
        let end = bounds.upper(self.len());
        while i < end { out.push(self.get(i)); i = i + 1; }
        return out;
    }

    // Replaces the clamped `bounds` with `values`, which may have a different length.
    pub def replace_range(bounds: IndexRange, values: Vec<T>) -> Void {
        let start = bounds.lower(self.len());
        var end = bounds.upper(self.len()); if end < start { end = start; }
        let incoming = values.slice(IndexRange { start: 0, end: values.len(), inclusive: false });
        let tail = self.slice(IndexRange { start: end, end: self.len(), inclusive: false });
        while self.len() > start { self.pop(); }
        for value in incoming { self.push(value); }
        for value in tail { self.push(value); }
    }

    pub def __iter__() -> VecIter<T> {
        return VecIter<T> { vec: self, pos: 0 };
    }

    pub def swap(first: i32, second: i32) -> Void {
        let held = self.get(first);
        self.set(first, self.get(second));
        self.set(second, held);
    }
    pub def reverse() -> Void {
        var low = 0; var high = self.len() - 1;
        while low < high { self.swap(low, high); low += 1; high -= 1; }
    }
    pub def reversed() -> Vec<T> {
        let out = Vec<T>.with_capacity(self.len());
        var index = self.len() - 1;
        while index >= 0 { out.push(self.get(index)); index -= 1; }
        out
    }

    // Sorts in place so that `less(a, b)` holds for no later a before earlier b.
    // Stable: equal elements keep their order. O(n log n) comparisons.
    pub def sort_by(less: (T, T) -> Bool) -> Void {
        let count = self.len();
        if count < 2 { return; }
        // Insertion-sorted runs, then bottom-up merges alternating with a buffer.
        var start = 0;
        while start < count {
            var end = start + 16; if end > count { end = count; }
            var index = start + 1;
            while index < end {
                let value = self.get(index);
                var slot = index;
                while slot > start && less(value, self.get(slot - 1)) { self.set(slot, self.get(slot - 1)); slot -= 1; }
                self.set(slot, value);
                index += 1;
            }
            start = end;
        }
        var from = self;
        var into = self.slice(0..<count);
        var width = 16;
        while width < count {
            var low = 0;
            while low < count {
                var middle = low + width; if middle > count { middle = count; }
                var high = low + 2 * width; if high > count { high = count; }
                var left = low; var right = middle; var out = low;
                while out < high {
                    if left < middle && (right >= high || !less(from.get(right), from.get(left))) { into.set(out, from.get(left)); left += 1; }
                    else { into.set(out, from.get(right)); right += 1; }
                    out += 1;
                }
                low = high;
            }
            let swapped = from; from = into; into = swapped;
            width *= 2;
        }
        // After an odd number of passes the result is in the buffer.
        if from.handle != self.handle { for index in 0..<count { self.set(index, from.get(index)); } }
    }
    pub def sorted_by(less: (T, T) -> Bool) -> Vec<T> {
        let copy = self.slice(0..<self.len());
        copy.sort_by(less);
        copy
    }
    // In a vector partitioned by `predicate` (true elements first), the index
    // of the first false element; the length when all are true.
    pub def partition_point(predicate: (T) -> Bool) -> i32 {
        var low = 0; var high = self.len();
        while low < high {
            let middle = low + (high - low) / 2;
            if predicate(self.get(middle)) { low = middle + 1; } else { high = middle; }
        }
        low
    }
    // In a sorted vector, an index whose element `order` maps to 0, or nil.
    // `order(element)` is negative for elements before the target and
    // positive for elements after it.
    pub def binary_search_by(order: (T) -> i32) -> i32? {
        var low = 0; var high = self.len();
        while low < high {
            let middle = low + (high - low) / 2;
            let result = order(self.get(middle));
            if result == 0 { return middle; }
            if result < 0 { low = middle + 1; } else { high = middle; }
        }
        nil
    }
    // The index of the first element satisfying `predicate`, or nil.
    pub def index_where(predicate: (T) -> Bool) -> i32? {
        for index in 0..<self.len() { if predicate(self.get(index)) { return index; } }
        nil
    }

    pub def len() -> i32 {
        unsafe { return rt_gvec_len(self.handle); }
    }

    pub def pop() -> T {
        var out: T;
        unsafe { rt_gvec_pop(self.handle, out as RawPtr); }
        return out;
    }

    pub def resize(new_capacity: i32) -> Void {
        unsafe { self.handle = rt_gvec_resize(self.handle, new_capacity); }
    }

    // Exposes the underlying gvec handle so cross-module stdlib helpers
    // (and the runtime FFI) can read the buffer without violating field
    // visibility. Marked `unsafe` because callers can read past the
    // vec's length, free the buffer prematurely, or hand the raw pointer
    // to functions that interpret it incorrectly.
    pub unsafe def raw_handle() -> RawPtr {
        return self.handle;
    }
}

// Runtime constructor behind Vec.new/with_capacity; elem_type_id is nonzero for
// managed element types.
def vec_new<T>(capacity: i32, elem_size: i32, elem_type_id: i32) -> Vec<T> {
    var result: Vec<T>;
    unsafe { result.handle = rt_gvec_new(capacity, elem_size, elem_type_id); }
    result.elem_size = elem_size;
    return result;
}

// ============================================================================
// VecIter<T> — element iterator for Vec<T>.
//
// Used by the for-in loop protocol (__iter__ / __next__). Vec.__iter__()
// returns a VecIter that yields each element by value via vec.get().
// ============================================================================

pub struct VecIter<T> {
    var vec: Vec<T>;
    var pos: i32;

    pub def __iter__() -> VecIter<T> { return self; }

    pub def __next__() -> T? {
        if self.pos < self.vec.len() {
            let elem = self.vec.get(self.pos);
            self.pos = self.pos + 1;
            return elem;
        }
        return nil;
    }
}
