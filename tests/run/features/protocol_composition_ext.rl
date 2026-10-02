protocol A { def a() -> i32; }
protocol C { def c() -> i32; }
struct S { var n: i32; }
extension S: A, C { def a() -> i32 { 41 } def c() -> i32 { 1 } }
def sum<T: A & C>(t: T) -> i32 { t.a() + t.c() }
def main() -> i32 { if sum(S { n: 0 }) == 42 { return 0; } 1 }
