protocol P { def v() -> i32; }
struct A: P { var n: i32; def v() -> i32 { self.n } }
struct B: P { var k: i32; def v() -> i32 { 2 } }
def main() -> i32 { let xs: [any P] = [A { n: 40 }, B { k: 0 }]; var s = 0; for x in xs { s += x.v(); } if s == 42 { return 0; } 1 }
