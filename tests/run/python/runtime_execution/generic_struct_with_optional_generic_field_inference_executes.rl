// expect-exit: 42

struct InnerOG<T> { var v: T }
struct OuterOG<T> {
    var i: InnerOG<T>?
    def value(d: T) -> T {
        if let x = self.i { return x.v; }
        return d;
    }
}
def main() -> i32 {
    let o = OuterOG { i: InnerOG { v: 42 } };
    o.value(0)
}
