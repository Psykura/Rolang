// expect-exit: 134

import "panic.rl"
import "io.rl"

def main() -> i32 {
    println("before");
    panic("explicit panic for test");
    return 0;
}
