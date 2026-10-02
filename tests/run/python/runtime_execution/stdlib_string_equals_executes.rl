
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("abc".equals("abc"));
    if r != 0 { return r; }
    r = assert_false("abc".equals("xyz"));
    if r != 0 { return r; }
    return 0;
}
