// expect-exit: 42

protocol Val { def val() -> i32; }
struct X { var n: i32; def val() -> i32 { self.n } }
struct Y { var m: i32; def val() -> i32 { self.m } }

struct WithWhere<T> where T: Val {
    var inner: T;
    def get() -> i32 { return self.inner.val(); }
}

struct WithInline<T: Val> {
    var inner: T;
    def get() -> i32 { return self.inner.val(); }
}

def main() -> i32 {
    let a = WithWhere<X> { inner: X { n: 10 } };
    let b = WithInline<Y> { inner: Y { m: 32 } };
    return a.get() + b.get();
}
