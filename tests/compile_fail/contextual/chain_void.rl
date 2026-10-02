// expect-error: INVALID_OPERATION: Optional chaining cannot call 'touch' because it returns Void; unwrap the value with if let
struct S { var n: i32; def touch() -> Void { self.n = 1; } }
def main() -> i32 { let s: S? = S { n: 0 }; s?.touch(); 0 }
