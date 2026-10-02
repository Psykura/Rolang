// expect-exit: 4

import "string.rl"
import "io.rl"

def main() -> i32 {
    let v = "a,b,c,d".split(",");
    let n = v.len();
    var i: i32 = 0;
    while i < n {
        println(v.get(i));
        i = i + 1;
    }
    return n;
}
