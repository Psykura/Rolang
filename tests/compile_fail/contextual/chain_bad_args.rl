// expect-error: TYPE_MISMATCH: Cannot assign String to i32 in argument 1
struct S { var n: i32; def add(x: i32) -> i32 { self.n + x } }
def main() -> i32 { let s: S? = S { n: 0 }; let v = s?.add("x"); 0 }
