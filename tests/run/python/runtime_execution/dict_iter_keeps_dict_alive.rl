// expect-exit: 9

import "dict.rl"
import "iter.rl"

def make_dict() -> Dict<String, i64> {
    var d = Dict<String, i64>.new();
    d.set("ab", 1); d.set("cde", 2); d.set("fghi", 3);
    return d;
}

def main() -> i32 {
    var total: i32 = 0;
    for k in dict_keys(make_dict()) {
        // Churn the allocator: if the temporary dict were freed (the UAF), this
        // would reuse its storage and corrupt the keys read below.
        var junk = Dict<String, i64>.new();
        junk.set("zzzzzzzzzzzzzzzz", 999);
        junk.set("yyyyyyyyyyyyyyyy", 888);
        total = total + (k.len() as i32);
    }
    return total;  // 2 + 3 + 4 = 9
}
