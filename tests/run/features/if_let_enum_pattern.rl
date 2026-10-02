enum T { case num(i32); case none; }
def main() -> i32 { let t = T.num(42); if let .num(n) = t { if n == 42 { return 0; } } 1 }
