def f(x: i32) -> i32 { guard x > 0 else { return 0; } x }
def main() -> i32 { if f(42) == 42 && f(-1) == 0 { return 0; } 1 }
