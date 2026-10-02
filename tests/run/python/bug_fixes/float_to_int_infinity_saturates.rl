
import "io.rl"

def main() -> i32 {
    let big: f64 = 1.0e300;
    let n: i32 = big as i32;
    // INT32_MAX = 2147483647, fits in i32
    if n == 2147483647 { return 0; }
    return n;
}
