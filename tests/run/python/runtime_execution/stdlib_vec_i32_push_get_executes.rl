
import "vec.rl"
import "test.rl"

def main() -> i32 {
    var v = Vec<i32>.new();
    v.push(42);
    v.push(99);
    var r = assert_eq_i32(v.len(), 2);
    if r != 0 { return r; }
    r = assert_eq_i32(v.get(0), 42);
    if r != 0 { return r; }
    r = assert_eq_i32(v.get(1), 99);
    if r != 0 { return r; }
    return 0;
}
