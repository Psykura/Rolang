
import "math.rl"

def main() -> i32 {
    if (3).min(7) != 3 { return 1; }
    if (3).max(7) != 7 { return 1; }
    if (100).min(200) != 100 { return 1; }
    if (100).max(200) != 200 { return 1; }
    return 0;
}
