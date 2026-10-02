// expect-error: Cannot compare i32 with nil: i32 is not optional
def main() -> i32 { let x = 1; if x == nil { return 1; } 0 }
