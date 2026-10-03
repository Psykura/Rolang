import std.io
import std.json
protocol Make { static def make(n: i32) -> Self; def value() -> i32; }
struct A: Make { let v: i32; static def make(n: i32) -> A { A { v: n } } def value() -> i32 { self.v } }
extension i32: Make { static def make(n: i32) -> i32 { n * 2 } def value() -> i32 { self } }
def total<T: Make>(values: Vec<i32>) -> i32 { var sum = 0; for v in values { sum += T.make(v).value(); } sum }
def first<T>(items: Vec<T>) -> T { items[0] }
def pair<A, B>(a: A, b: B) -> (A, B) { (a, b) }
def main() -> i32 {
    println(f"{total<A>([1, 2])} {total<i32>([1, 2])} {first<i64>([5])} {pair<i64, String>(1, "x").1}");
    let decoded = decode_json<Vec<i32>>("[1, 2, 3]");
    println(f"{decoded.ok_value()?.len() ?? 0}");
    let x = 3; let y = 5;
    if x < y && y > (x) { println("comparisons still work"); }
    0
}
