// expect-error: Type 'Z' does not conform to protocol 'P' (required by 'T: P')
protocol P { def v() -> i32; }
struct Z { var n: i32; }
def use<T: P>(t: T) -> i32 { t.v() }
def main() -> i32 { use(Z { n: 1 }) }
