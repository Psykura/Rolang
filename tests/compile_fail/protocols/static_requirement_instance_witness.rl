// expect-error: Method 'make' must be a static method
protocol Make { static def make(n: i32) -> Self; }
struct A: Make { let v: i32; def make(n: i32) -> A { A { v: n } } }
def main() -> i32 { 0 }
