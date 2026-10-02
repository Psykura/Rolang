enum T { case num(i32); case none; }
def main() -> i32 { let t = T.num(42); guard let .num(n) = t else { return 1; } if n == 42 { return 0; } 1 }
