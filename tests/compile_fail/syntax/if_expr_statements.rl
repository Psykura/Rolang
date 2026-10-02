// expect-error: expected '}' (if expression branches hold a single expression)
def main() -> i32 { let x = if true { let y = 1; y } else { 2 }; x }
