
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("hello".substring(1, 3).equals("ell"));
    if r != 0 { return r; }
    r = assert_true("abc".substring(0, 2).equals("ab"));
    if r != 0 { return r; }
    return 0;
}
