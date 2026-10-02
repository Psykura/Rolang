// expect-exit: 3

import "iter.rl"
import "io.rl"

def main() -> i32 {
    var count: i32 = 0;
    for ch in chars_of("abc") {
        count = count + 1;
        println(f"{ch}");
    }
    return count;
}
