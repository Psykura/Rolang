
import "vec.rl"
import "test.rl"

def main() -> i32 {
    var v = Vec<i64>.new();
    v.push(100);
    v.push(200);
    var r = assert_eq_i64(v.get(0), 100);
    if r != 0 { return r; }
    r = assert_eq_i64(v.get(1), 200);
    if r != 0 { return r; }
    return 0;
}
