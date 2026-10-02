struct S { var a: i32 = 40; var b: i32; }
def main() -> i32 { let s = S { b: 2 }; if s.a + s.b == 42 { return 0; } 1 }
