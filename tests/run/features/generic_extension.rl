struct Box<T> { var v: T; }
extension<T> Box<T> { def get() -> T { self.v } static def of(v: T) -> Box<T> { Box<T> { v: v } } }
def main() -> i32 { if Box<i32>.of(42).get() == 42 { return 0; } 1 }
