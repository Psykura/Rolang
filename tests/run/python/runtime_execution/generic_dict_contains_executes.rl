// expect-exit: 1

import "dict.rl"

def main() -> i32 {
    var d = Dict<i32, i32>.new();
    d.set(1, 10);
    if d.contains(1) {
        return 1;
    }
    if d.contains(99) {
        return 2;
    }
    return 3;
}
