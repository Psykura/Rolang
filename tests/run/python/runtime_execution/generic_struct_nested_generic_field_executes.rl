// expect-exit: 42

struct InnerGen<T> { var v: T }
struct WrapGen<U> {
    var inner: InnerGen<U>
    def unwrap() -> U { self.inner.v }
}
def main() -> i32 {
    let w = WrapGen { inner: InnerGen { v: 42 } };
    w.unwrap()
}
