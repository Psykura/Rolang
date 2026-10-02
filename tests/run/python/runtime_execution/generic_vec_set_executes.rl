// expect-exit: 120

import "vec.rl"

def main() -> i32 {
    var v = Vec<i32>.new();
    v.push(10);
    v.push(20);
    v.set(0, 100);
    return v.get(0) + v.get(1);
}
