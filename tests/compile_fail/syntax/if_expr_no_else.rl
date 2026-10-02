// expect-error: expected 'else' (an if expression needs both branches)
def main() -> i32 { let x = if true { 1 }; x }
