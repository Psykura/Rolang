
import "io.rl"
def main() -> i32 {
    // Default i32 path
    println(f"{2147483647}");
    // Overflows i32 -> widens to i64 silently
    println(f"{2147483648}");
    return 0;
}
