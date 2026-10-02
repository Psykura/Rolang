protocol P { def v() -> i32; }
struct A { var n: i32; }
struct B { var n: i32; }
extension A: P { def v() -> i32 { self.n } }
extension B: P { def v() -> i32 { self.n } }
def main() -> i32 {
    let p: any P = A { n: 42 };
    let a = p as? A;
    let b = p as? B;
    let forced = p as! A;
    if (a?.n ?? 0) == 42 && b == nil && forced.n == 42 { return 0; }
    1
}
