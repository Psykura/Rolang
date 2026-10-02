// expect-error: cannot cast any P to S using `as`. Existential downcasts via `as` are not supported; use the runtime-

protocol P {
    def kind() -> i32;
}
struct S {
    var n: i32;
    def kind() -> i32 { self.n }
}
def main() -> i32 {
    let s = S { n: 7 };
    let x: any P = s;
    let back = x as S;
    return back.n;
}
