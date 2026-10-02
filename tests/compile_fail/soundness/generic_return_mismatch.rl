// expect-error: Cannot assign T to i32 in return value
def f<T>(t: T) -> i32 { t }
def main() -> i32 { f("x") }
