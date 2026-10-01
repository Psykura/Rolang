// Eager collection transforms. Inputs are borrowed; outputs own their elements.
// Callbacks must not structurally mutate the input vector during traversal.
import "vec.rl"
import "range.rl"
import "string.rl"
import "string_builder.rl"

pub def map_vec<T, U>(items: Vec<T>, transform: (T) -> U) -> Vec<U> {
    let out = Vec<U>.with_capacity(items.len());
    for item in items { out.push(transform(item)); }
    return out;
}

pub def filter_vec<T>(items: Vec<T>, predicate: (T) -> Bool) -> Vec<T> {
    let out = Vec<T>.new();
    for item in items { if predicate(item) { out.push(item); } }
    return out;
}

pub def fold_vec<T, U>(items: Vec<T>, initial: U, combine: (U, T) -> U) -> U {
    var result = initial;
    for item in items { result = combine(result, item); }
    return result;
}

pub def find_vec<T>(items: Vec<T>, predicate: (T) -> Bool) -> T? {
    for item in items { if predicate(item) { return item; } }
    return nil;
}

pub def any_vec<T>(items: Vec<T>, predicate: (T) -> Bool) -> Bool {
    for item in items { if predicate(item) { return true; } }
    return false;
}

pub def all_vec<T>(items: Vec<T>, predicate: (T) -> Bool) -> Bool {
    for item in items { if !predicate(item) { return false; } }
    return true;
}

// Half-open range, clamped to [0, len]. Returns a new vector, not a view.
pub def slice_vec<T>(items: Vec<T>, start: i32, end: i32) -> Vec<T> {
    return items[start..<end];
}

pub def join_strings(items: Vec<String>, separator: String) -> String {
    let out = StringBuilder.new();
    var first = true;
    for item in items {
        if !first { out.append(separator); }
        out.append(item);
        first = false;
    }
    return out.to_string();
}
