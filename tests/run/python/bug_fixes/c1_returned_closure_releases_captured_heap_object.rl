
import "io.rl"

struct R {
    var n: i32;

    def __release__() -> Void {
        println("captured release");
    }
}

def use_r(r: R, x: i32) -> i32 {
    return r.n + x;
}

def make() -> (i32) -> i32 {
    let r = R { n: 41 };
    return (x: i32) -> {
        return use_r(r, x);
    };
}

def main() -> i32 {
    let f = make();
    let y = f(1);
    println("after call");
    if y != 42 { return y; }
    return 0;
}
