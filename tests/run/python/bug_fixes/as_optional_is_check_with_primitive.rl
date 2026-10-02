
protocol Printable {
    def repr() -> i32;
}

struct Num {
    var v: i32;
    def repr() -> i32 { return self.v; }
}

def main() -> i32 {
    let n = Num { v: 99 };
    let p: any Printable = n;
    if p is Num { return 0; }
    return 1;
}
