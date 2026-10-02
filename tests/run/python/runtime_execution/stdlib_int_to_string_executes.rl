
import "string.rl"
import "test.rl"

def main() -> i32 {
    let x: i64 = 42;
    var r = assert_true(x.to_string().equals("42"));
    if r != 0 { return r; }
    let y: i64 = -7;
    r = assert_true(y.to_string().equals("-7"));
    if r != 0 { return r; }
    let z: i64 = 0;
    r = assert_true(z.to_string().equals("0"));
    if r != 0 { return r; }
    return 0;
}
