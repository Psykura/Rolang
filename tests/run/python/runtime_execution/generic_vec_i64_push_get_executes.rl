// expect-exit: 60

import "vec.rl"

def main() -> i32 {
    var v = Vec<i64>.new();
    v.push(10);
    v.push(20);
    v.push(30);
    let sum = v.get(0) + v.get(1) + v.get(2);
    return sum as i32;
}
