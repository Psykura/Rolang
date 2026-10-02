
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_eq_i32("abc".char_at(0), 97);
    if r != 0 { return r; }
    r = assert_eq_i32("abc".char_at(2), 99);
    if r != 0 { return r; }
    r = assert_eq_i32("abc".char_at(5), -1);
    if r != 0 { return r; }
    return 0;
}
