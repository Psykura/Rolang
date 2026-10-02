
import "io.rl"
import "vec.rl"
def wrap(x: i64) -> i64? { return x; }
def main() -> i32 {
    var v: Vec<i64?> = Vec<i64?>.new();
    v.push(wrap(1234567890123456));
    v.push(wrap(9876543210987654));
    switch v.get(0) {
        case .Some(let x): println(f"{x}");
        case nil: println(f"{-1}");
    }
    switch v.get(1) {
        case .Some(let x): println(f"{x}");
        case nil: println(f"{-1}");
    }
    return 0;
}
