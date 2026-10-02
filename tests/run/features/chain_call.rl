struct S { var n: i32; def get() -> i32 { self.n } }
def main() -> i32 { let s: S? = S { n: 42 }; if (s?.get() ?? 0) == 42 { return 0; } 1 }
