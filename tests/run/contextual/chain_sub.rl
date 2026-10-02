struct S { var v: [i32]; }
def main() -> i32 { let s: S? = S { v: [42] }; if (s?.v[0] ?? 0) == 42 { return 0; } 1 }
