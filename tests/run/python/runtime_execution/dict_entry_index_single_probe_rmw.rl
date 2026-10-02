// expect-exit: 8

import "dict.rl"
import "string.rl"
import "vec.rl"

def make_key(n: i64) -> String {
    let alpha = "0123456789";
    var x = n; var s = "k";
    while x > 0 { s = s + alpha.substring((x % 10) as i32, 1); x = x / 10; }
    return s;
}

def main() -> i32 {
    var keys = Vec<String>.with_capacity(4);
    keys.push("a"); keys.push("b"); keys.push("c");

    var d = Dict<String, i64>.new();
    var ok: i32 = 0;

    // Insert "a" with default 0, then increment to 1 (single-probe RMW).
    let ia = d.entry_index(keys.get(0), 0 as i64);
    d.set_value_at(ia, d.value_at(ia) + 1 as i64);
    let ib = d.entry_index(keys.get(1), 0 as i64);
    d.set_value_at(ib, d.value_at(ib) + 1 as i64);
    // Re-entry of "a" must return the same index and see the current value.
    let ia2 = d.entry_index(keys.get(0), 0 as i64);
    d.set_value_at(ia2, d.value_at(ia2) + 1 as i64);

    if ia == ia2 { ok = ok + 1; }                            // stable index
    if d.value_at(ia) == 2 { ok = ok + 1; }                  // a incremented twice
    if d.value_at(ib) == 1 { ok = ok + 1; }                  // b once
    if (d.get(keys.get(0)) ?? 0) == 2 { ok = ok + 1; }       // hashed get agrees
    if d.len() == 2 { ok = ok + 1; }                         // exactly two keys

    // get-or-insert default: absent "c" gets default 9.
    let ic = d.entry_index(keys.get(2), 9 as i64);
    if d.value_at(ic) == 9 { ok = ok + 1; }
    if d.len() == 3 { ok = ok + 1; }

    // Index stability across many inserts (forces a resize); re-check "a".
    var n: i64 = 0;
    while n < 200 { d.entry_index(make_key(n), n); n = n + 1; }
    if d.value_at(ia) == 2 { ok = ok + 1; }                  // ia still valid post-resize

    return ok;  // expect 8
}
