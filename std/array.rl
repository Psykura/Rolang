import "range.rl"
// Standard library: numeric helpers on Vec<i32>.

import "vec.rl"

// ---- Sum / Product ----

pub def array_sum(arr: Vec<i32>) -> i32 {
    var total = 0;
    let len = arr.len();
    for i in 0..<len {
        total = total + arr.get(i);
    }
    return total;
}

pub def array_product(arr: Vec<i32>) -> i32 {
    var result = 1;
    let len = arr.len();
    for i in 0..<len {
        result = result * arr.get(i);
    }
    return result;
}

// ---- Search ----

pub def array_contains(arr: Vec<i32>, value: i32) -> Bool {
    let len = arr.len();
    for i in 0..<len {
        if arr.get(i) == value { return true; }
    }
    return false;
}

pub def array_find(arr: Vec<i32>, value: i32) -> i32 {
    let len = arr.len();
    for i in 0..<len {
        if arr.get(i) == value { return i; }
    }
    return -1;
}

pub def array_count(arr: Vec<i32>, value: i32) -> i32 {
    var count = 0;
    let len = arr.len();
    for i in 0..<len {
        if arr.get(i) == value { count = count + 1; }
    }
    return count;
}

// ---- Min/Max (convenience) ----
//
// Both return nil for an empty vector. Use `?? default` or `unwrap_or()`
// to supply a fallback.

pub def array_min(arr: Vec<i32>) -> i32? {
    let len = arr.len();
    if len <= 0 { return nil; }
    var m = arr.get(0);
    for i in 1..<len {
        let v = arr.get(i);
        if v < m { m = v; }
    }
    return m;
}

pub def array_max(arr: Vec<i32>) -> i32? {
    let len = arr.len();
    if len <= 0 { return nil; }
    var m = arr.get(0);
    for i in 1..<len {
        let v = arr.get(i);
        if v > m { m = v; }
    }
    return m;
}
