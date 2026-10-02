struct C { var v: i32; }
def main() -> i32 { let c = C { v: 0 }; for i in 0..<3 { defer { c.v = c.v * 10 + i; } } if c.v == 12 { return 0; } 1 }
