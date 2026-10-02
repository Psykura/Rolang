def main() -> i32 { let a: (i32?)? = 42; if let inner = a { if let v = inner { if v == 42 { return 0; } } } 1 }
