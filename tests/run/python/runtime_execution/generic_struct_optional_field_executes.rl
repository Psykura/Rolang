// expect-exit: 42

struct OptBox<T> {
    var v: T?
    def or_default(d: T) -> T {
        if let x = self.v { return x; }
        return d;
    }
}
def main() -> i32 {
    let b = OptBox<i32> { v: 42 };
    b.or_default(0)
}
