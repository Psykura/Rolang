// Standard library: generic Set<T>
//
// Backed by Dict<T, i32> with all values set to 1, so elements compare like
// dictionary keys: String by content, other types by their bytes.
//
// Snapshot values follow insertion order, as in the underlying dictionary.

import "dict.rl"
import "vec.rl"
import "string.rl"

pub struct Set<T> {
    var d: Dict<T, i32>;

    // An empty set; String elements compare by content, others by their bytes.
    pub static def new() -> Set<T> { Set<T> { d: Dict<T, i32>.new() } }

    // dict.set is an upsert, so we don't return a "was new?" signal;
    // callers needing it should `contains` first.
    pub def add(elem: T) -> Void {
        self.d.set(elem, 1);
    }

    pub def contains(elem: T) -> Bool {
        return self.d.contains(elem);
    }

    pub def len() -> i64 {
        return self.d.len();
    }

    pub def is_empty() -> Bool {
        return self.d.len() == 0;
    }

    pub def remove(elem: T) -> Bool {
        if let removed = self.d.remove(elem) { return true; }
        return false;
    }

    pub def clear() -> Void { self.d.clear(); }

    pub def values() -> Vec<T> { return self.d.keys(); }
}
