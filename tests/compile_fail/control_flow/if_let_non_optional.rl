// expect-error: TYPE_MISMATCH: `let` in if condition needs an optional value or a refutable pattern such as an enum case; i32 is not opt
def main() -> i32 { let x = 1; if let y = x { return y; } 0 }
