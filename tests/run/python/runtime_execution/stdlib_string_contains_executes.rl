
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("hello".contains("ell"));
    if r != 0 { return r; }
    r = assert_false("hello".contains("world"));
    if r != 0 { return r; }
    r = assert_true("file.rl".starts_with("file"));
    if r != 0 { return r; }
    r = assert_true("file.rl".ends_with(".rl"));
    if r != 0 { return r; }
    r = assert_false("file.rl".ends_with(".rs"));
    if r != 0 { return r; }
    return 0;
}
