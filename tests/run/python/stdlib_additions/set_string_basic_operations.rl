
import "set.rl"

def main() -> i32 {
    var s = Set<String>.new();
    s.add("alpha");
    s.add("beta");
    s.add("alpha");  // duplicate
    s.add("gamma");
    if s.len() != 3 { return 1; }
    if !s.contains("alpha") { return 2; }
    if !s.contains("gamma") { return 3; }
    if s.contains("missing") { return 4; }
    if s.is_empty() { return 5; }
    return 0;
}
