
import "set.rl"

def main() -> i32 {
    var s = Set<i32>.new();
    s.add(10);
    s.add(20);
    s.add(10);  // dup
    if s.len() != 2 { return 1; }
    if !s.contains(10) { return 2; }
    if s.contains(99) { return 3; }
    return 0;
}
