
import "math.rl"

def main() -> i32 {
    if (-42).abs() != 42 { return 1; }
    if (0).abs() != 0 { return 1; }
    if (7).abs() != 7 { return 1; }
    return 0;
}
