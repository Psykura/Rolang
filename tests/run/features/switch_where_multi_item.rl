def f(n: i32) -> i32 { switch n { case let x where x > 100, 7: 1; default: 0; } }
def main() -> i32 { if f(200) + f(7) == 2 && f(5) == 0 { return 0; } 1 }
