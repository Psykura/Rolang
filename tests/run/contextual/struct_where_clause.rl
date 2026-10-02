protocol P { def v() -> i32; }
struct A { var n: i32; }
extension A: P { def v() -> i32 { self.n } }
struct Holder<T> where T: P { var t: T; def get() -> i32 { self.t.v() } }
def main() -> i32 { if Holder<A> { t: A { n: 42 } }.get() == 42 { return 0; } 1 }
