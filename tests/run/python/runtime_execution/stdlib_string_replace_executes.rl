
import "string.rl"
import "test.rl"

def main() -> i32 {
    var r = assert_true("hello world".replace("world", "rolang").equals("hello rolang"));
    if r != 0 { return r; }
    r = assert_true("a,b,c".replace(",", "-").equals("a-b-c"));
    if r != 0 { return r; }
    r = assert_true("abc".replace("x", "y").equals("abc"));
    if r != 0 { return r; }
    return 0;
}
