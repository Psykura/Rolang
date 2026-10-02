
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("ha".repeat(3).equals("hahaha"));
    if r != 0 { return r; }
    r = assert_true("x".repeat(1).equals("x"));
    if r != 0 { return r; }
    r = assert_eq_i64("ab".repeat(4).len(), 8);
    if r != 0 { return r; }
    return 0;
}
