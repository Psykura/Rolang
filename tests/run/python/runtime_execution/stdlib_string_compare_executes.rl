
import "string.rl"

def main() -> i32 {
    if "a".compare_to("b") >= 0 { return 1; }
    if "b".compare_to("a") <= 0 { return 1; }
    if "abc".compare_to("abc") != 0 { return 1; }
    return 0;
}
