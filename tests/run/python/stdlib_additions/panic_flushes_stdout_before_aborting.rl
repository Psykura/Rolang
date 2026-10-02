// expect-exit: 134

import "panic.rl"
import "io.rl"

def main() -> i32 {
    println("MARKER_LINE");
    panic("oops");
    return 0;
}
