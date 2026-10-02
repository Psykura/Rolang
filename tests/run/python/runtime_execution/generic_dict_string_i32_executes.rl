// expect-exit: 22

import "dict.rl"

def main() -> i32 {
    var d = Dict<String, i32>.new();
    d.set("a", 5);
    d.set("b", 10);
    d.set("c", 7);
    let sum = (d.get("a") ?? 0) + (d.get("b") ?? 0) + (d.get("c") ?? 0);
    return sum;
}
