
import "io.rl"

struct Cell {
    var n: i32;
    def __release__() -> Void { /* nothing — just allocates */ }
}

def main() -> i32 {
    var i: i32 = 0;
    while i < 20000 {
        let _ = Cell { n: i };
        i = i + 1;
    }
    println(f"{i}");
    return 0;
}
