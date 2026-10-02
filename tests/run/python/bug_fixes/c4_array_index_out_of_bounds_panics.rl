// expect-exit: 134

import "io.rl"

def main() -> i32 {
    let a = [10, 20, 30];
    let x = a[10];
    println(f"{x}");
    return 0;
}
