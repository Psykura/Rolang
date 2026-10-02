
import "io.rl"

protocol Valued {
    def value() -> i32;
}

struct R {
    var n: i32;

    def value() -> i32 {
        return self.n;
    }

    def __release__() -> Void {
        println("existential release");
    }
}

def make() -> any Valued {
    let r = R { n: 42 };
    return r;
}

def main() -> i32 {
    let p = make();
    let y = p.value();
    println("after call");
    if y != 42 { return y; }
    return 0;
}
