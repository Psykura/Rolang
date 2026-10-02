protocol A { def a() -> i32; }
protocol B: A { def b() -> i32; }
protocol C { def c() -> i32; }
struct S { var n: i32; }
extension S: B { def a() -> i32 { 40 } def b() -> i32 { 1 } }
extension S: C { def c() -> i32 { 1 } }
def sum<T: B & C>(t: T) -> i32 { t.a() + t.b() + t.c() }
def main() -> i32 { if sum(S { n: 0 }) == 42 { return 0; } 1 }
