// expect-error: INVALID_OPERATION: Cannot compare i32 and $__nil
def main() -> i32 { let x = 1; if x == nil { return 1; } 0 }
