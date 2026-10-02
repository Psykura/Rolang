def main() -> i32 { let x: i32 = 42; let o: i32? = 1; if (x is i32) && !(x is i64) && (o is i32) { return 0; } 1 }
