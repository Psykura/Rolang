
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("  hi  ".trim().equals("hi"));
    if r != 0 { return r; }
    r = assert_true("abc".trim().equals("abc"));
    if r != 0 { return r; }
    r = assert_true("   ".trim().equals(""));
    if r != 0 { return r; }
    return 0;
}
