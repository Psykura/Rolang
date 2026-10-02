struct S { var n: i32; }
extension S { static def make() -> S { S { n: 42 } } }
def main() -> i32 { if S.make().n == 42 { return 0; } 1 }
