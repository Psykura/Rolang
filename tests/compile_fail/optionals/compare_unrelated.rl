// expect-error: Cannot compare String and i32
def main() -> i32 { let s: String? = "x"; if s == 5 { return 1; } 0 }
