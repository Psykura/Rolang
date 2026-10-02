protocol P { def v() -> i32; }
struct A { var n: i32; def v() -> i32 { self.n } }
def use<T: P>(t: T) -> i32 { t.v() }
def main() -> i32 { if use(A { n: 42 }) == 42 { return 0; } 1 }
