protocol P { def v() -> i32; }
enum E { case a; }
extension E: P { def v() -> i32 { 42 } }
def main() -> i32 { let x: any P = E.a; if x.v() == 42 { return 0; } 1 }
