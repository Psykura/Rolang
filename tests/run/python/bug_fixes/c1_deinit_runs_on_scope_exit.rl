
import "io.rl"

struct R {
    var n: i32;

    def __release__() -> Void {
        println("deinit ran");
    }
}

def main() -> i32 {
    let _ = R { n: 1 };
    println("before scope end");
    return 0;
}
