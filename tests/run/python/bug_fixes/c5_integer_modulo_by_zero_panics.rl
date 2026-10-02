// expect-exit: 134

import "io.rl"

def main() -> i32 {
    var b: i32 = 0;
    let r = 10 % b;
    println(f"{r}");
    return 0;
}
