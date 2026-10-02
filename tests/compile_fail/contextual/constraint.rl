// expect-error: Type 'Z' does not conform to protocol 'P' (required by 'T: P')
protocol P { def v() -> i32; }
struct Z { var n: i32; }
struct Holder<T: P> { var t: T; }
def main() -> i32 { let h = Holder<Z> { t: Z { n: 1 } }; 0 }
