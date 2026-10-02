struct S { var n: i32; static def zero() -> S { S { n: 0 } } }
def main() -> i32 { let s = S.zero(); if s.n == 0 { return 0; } 1 }
