// expect-exit: 25

import "dict.rl"

def main() -> i32 {
    var d = Dict<i32, i32>.new();
    d.set(1, 10);
    d.set(1, 25);
    return d.get(1) ?? 0;
}
