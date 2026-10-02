// expect-error: TYPE_MISMATCH: S is not a protocol and cannot be inherited
struct S { var n: i32; }
protocol P: S { def f() -> i32; }
def main() -> i32 { 0 }
