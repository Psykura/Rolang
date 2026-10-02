// expect-error: argument 1 label mismatch: expected first, got second

def add(first x: i32) -> i32 { return x; }
def main() -> i32 { return add(second: 1); }
