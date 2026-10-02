struct Box<T> { var v: T; static def new(v: T) -> Box<T> { Box<T> { v: v } } }
def main() -> i32 { let b = Box<i32>.new(42); if b.v == 42 { return 0; } 1 }
