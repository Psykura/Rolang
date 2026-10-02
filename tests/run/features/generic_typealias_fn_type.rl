typealias Fn<T> = (T) -> T;
def apply(f: Fn<i32>, x: i32) -> i32 { f(x) }
def main() -> i32 { if apply((x) -> { x * 2 }, 21) == 42 { return 0; } 1 }
