// expect-exit: 5

import "dict.rl"
import "iter.rl"

def main() -> i32 {
    var d = Dict<String, i64>.new();
    d.set("ab", 1);
    d.set("cde", 2);
    var total: i32 = 0;
    for k in dict_keys(d) {
        total = total + (k.len() as i32);
    }
    return total;
}
