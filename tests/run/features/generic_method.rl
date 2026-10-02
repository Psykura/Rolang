struct Box<T> { var v: T; def map<U>(f: (T) -> U) -> Box<U> { Box<U> { v: f(self.v) } } }
def main() -> i32 { let b = Box<i32> { v: 21 }.map((x) -> { x * 2 }); if b.v == 42 { return 0; } 1 }
