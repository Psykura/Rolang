// expect-exit: 32

import "vec.rl"

def main() -> i32 {
    var v = Vec<i32>.new();
    v.push(10);
    v.push(20);
    v.push(30);
    let last = v.pop();
    return last + v.len();
}
