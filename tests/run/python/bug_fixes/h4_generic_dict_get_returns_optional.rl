
import "io.rl"
import "dict.rl"

def main() -> i32 {
    var d = Dict<i32, i32>.new();
    d.set(1, 0);  // present, value happens to be 0
    let present = d.get(1) ?? -1;        // expect 0
    let missing = d.get(2) ?? -1;        // expect -1
    println(f"{present}");
    println(f"{missing}");
    return 0;
}
