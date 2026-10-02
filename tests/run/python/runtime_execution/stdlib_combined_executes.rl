
import "math.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_eq_i32((2).pow(3), 8);
    if r != 0 { return r; }
    r = assert_eq_i32(((10).min(5)).max(0), 5);
    if r != 0 { return r; }
    return 0;
}
