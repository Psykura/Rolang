// expect-error: TYPE_MISMATCH: Cannot assign $T to i32 in argument 1
def takes(n: i32) -> i32 { n }
def h<T>(t: T) -> i32 { takes(t) }
def main() -> i32 { h(1) }
