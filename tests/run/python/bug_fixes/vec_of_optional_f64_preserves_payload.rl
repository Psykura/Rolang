
import "io.rl"
import "vec.rl"
def wrap(x: f64) -> f64? { return x; }
def main() -> i32 {
    var v: Vec<f64?> = Vec<f64?>.new();
    v.push(wrap(314.0));
    v.push(wrap(271.0));
    var total: f64 = 0.0;
    switch v.get(0) {
        case .Some(let x): total = total + x;
        case nil: println(f"{-1}");
    }
    switch v.get(1) {
        case .Some(let x): total = total + x;
        case nil: println(f"{-1}");
    }
    // 314 + 271 = 585; result fits in i64 cleanly.
    println(f"{total as i64}");
    return 0;
}
