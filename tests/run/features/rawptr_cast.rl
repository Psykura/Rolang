struct S { var n: i32; }
def main() -> i32 { let s = S { n: 42 }; unsafe { let p = s as RawPtr; let back = p as S; if back.n == 42 { return 0; } } 1 }
