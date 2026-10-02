
import "io.rl"

def main() -> i32 {
    let nan: f64 = 0.0 / 0.0;
    let n: i32 = nan as i32;
    return n;
}
