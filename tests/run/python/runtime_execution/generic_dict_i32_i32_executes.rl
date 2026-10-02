// expect-exit: 35

import "dict.rl"

def main() -> i32 {
    var d = Dict<i32, i32>.new();
    d.set(1, 10);
    d.set(2, 20);
    d.set(3, 5);
    let sum = (d.get(1) ?? 0) + (d.get(2) ?? 0) + (d.get(3) ?? 0);
    return sum;
}
