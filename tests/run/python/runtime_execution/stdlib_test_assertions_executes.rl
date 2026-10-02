
import "test.rl"

def main() -> i32 {
    var r = assert_eq_i32(42, 42);
    if r != 0 { return r; }
    r = assert_eq_i64(100, 100);
    if r != 0 { return r; }
    r = assert_true(true);
    if r != 0 { return r; }
    r = assert_false(false);
    if r != 0 { return r; }
    return 0;
}
