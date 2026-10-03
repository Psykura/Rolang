// Static protocol requirements are called through a bounded type parameter.
protocol Make { static def make(n: i32) -> Self; def value() -> i32; }
struct A: Make { let v: i32; static def make(n: i32) -> A { A { v: n } } def value() -> i32 { self.v } }
extension i32: Make { static def make(n: i32) -> i32 { n * 2 } def value() -> i32 { self } }
extension i32 { static def parse_or(text: String, fallback: i32) -> i32 { if text.len() == 0 { return fallback; } text.to_i32() } }
def build<T: Make>(n: i32) -> T { T.make(n) }
def total<T: Make>(values: Vec<i32>, sample: T) -> i32 { var sum = sample.value(); for v in values { sum += T.make(v).value(); } sum }
def main() -> i32 {
    let a: A = build(3);
    let b: i32 = build(4);
    if a.v != 3 || b != 8 { return 1; }
    if total([1, 2], A { v: 0 }) != 3 || total([1, 2], 0) != 6 { return 2; }
    if i32.parse_or("", 5) != 5 || i32.parse_or("12", 0) != 12 { return 3; }
    0
}
