// expect-exit: 3

import "string.rl"
import "io.rl"

def main() -> i32 {
    let v = "hello\r\nworld\nbye".lines();
    let n = v.len();
    var i: i32 = 0;
    while i < n {
        println(v.get(i));
        i = i + 1;
    }
    return n;
}
