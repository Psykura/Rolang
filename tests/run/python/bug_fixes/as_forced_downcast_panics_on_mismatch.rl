// expect-exit: 134

protocol P {
    def val() -> i32;
}

struct A { var n: i32; def val() -> i32 { return self.n; } }
struct B { var n: i32; def val() -> i32 { return self.n; } }

def main() -> i32 {
    let a = A { n: 1 };
    let p: any P = a;
    let b: B = p as! B;   // mismatch — should panic
    return b.n;
}
