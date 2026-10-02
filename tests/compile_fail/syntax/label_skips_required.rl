// expect-error: argument 2 label mismatch: expected no label or 'factor', got 'offset'
def scale(value: i32, factor: i32, offset: i32 = 0) -> i32 { value * factor + offset }
def main() -> i32 { scale(5, offset: 1) }
