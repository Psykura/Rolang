
import "math.rl"

def main() -> i32 {
    if (2).pow(3) != 8 { return 1; }
    if (5).pow(0) != 1 { return 1; }
    if (3).pow(4) != 81 { return 1; }
    return 0;
}
