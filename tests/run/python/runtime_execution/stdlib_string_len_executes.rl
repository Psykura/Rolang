
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_eq_i64("hello".len(), 5);
    if r != 0 { return r; }
    r = assert_eq_i64("".len(), 0);
    if r != 0 { return r; }
    return 0;
}
