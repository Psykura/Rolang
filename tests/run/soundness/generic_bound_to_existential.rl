protocol P { def v() -> i32; }
struct S: P { var n: i32; def v() -> i32 { self.n } }
def box<T: P>(t: T) -> any P { t }
def main() -> i32 { if box(S { n: 42 }).v() == 42 { return 0; } 1 }
