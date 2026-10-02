
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("ab".concat("cd").equals("abcd"));
    if r != 0 { return r; }
    r = assert_true("".concat("xyz").equals("xyz"));
    if r != 0 { return r; }
    r = assert_eq_i64("a".concat("bc").len(), 3);
    if r != 0 { return r; }
    return 0;
}
