protocol P { def v() -> i32; }
struct A { var n: i32; }
extension A: P { def v() -> i32 { self.n } }
def get<T>(t: T) -> i32 where T: P { t.v() }
def main() -> i32 { if get(A { n: 42 }) == 42 { return 0; } 1 }
