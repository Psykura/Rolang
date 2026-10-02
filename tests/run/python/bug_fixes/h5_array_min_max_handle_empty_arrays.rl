
import "io.rl"
import "array.rl"

def main() -> i32 {
    let arr = [1, 2, 3];
    let empty = Vec<i32>.new();
    let m = array_max(empty) ?? -1;  // empty -> nil -> -1
    let p = array_max(arr) ?? -1;    // non-empty -> 3
    println(f"{m}");
    println(f"{p}");
    return 0;
}
