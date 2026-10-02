def f(x: (i32?)?) -> i32 { if let a = x { if let b = a { return b; } return 1; } 2 }
def main() -> i32 { let none: (i32?)? = nil; if f(42) == 42 && f(none) == 2 { return 0; } 1 }
