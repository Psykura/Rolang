
import "process.rl"
import "io.rl"

def main() -> i32 {
    let n = argc();
    var i: i32 = 1;
    while i < n {
        println(argv(i));
        i = i + 1;
    }
    return 0;
}
