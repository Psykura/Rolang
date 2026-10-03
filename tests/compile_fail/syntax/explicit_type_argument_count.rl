// expect-error: Function 'f' expects 1 type argument(s), got 2
def f<T>(x: T) -> T { x }
def main() -> i32 { f<i32, i64>(1) }
