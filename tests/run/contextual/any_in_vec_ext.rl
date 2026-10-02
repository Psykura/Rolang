protocol P { def v() -> i32; }
struct A { var n: i32; }
struct B { var k: i32; }
extension A: P { def v() -> i32 { self.n } }
extension B: P { def v() -> i32 { 2 } }
def main() -> i32 { let xs: [any P] = [A { n: 40 }, B { k: 0 }]; var s = 0; for x in xs { s += x.v(); } if s == 42 { return 0; } 1 }
