import std.io
struct Pair<A, B,> { let a: A; let b: B; }
enum Shape { case rect(i32, i32,); case dot; }
def add(a: i32, b: i32,) -> i32 { a + b }
def pair() -> (i32, String,) { (1, "x",) }
def main() -> i32 {
    let p = Pair<i32, String,> { a: add(1, 2,), b: "s", };
    let sum = (x: i32, y: i32,) -> { x + y };
    let d: [String: i32] = ["a": 1, "b": 2,];
    let v = [1, 2, 3,];
    let (n, text,) = pair();
    switch Shape.rect(1, 2,) { case .rect(let w, let h,): println(f"{w * h}"); case .dot: println("dot"); }
    println(f"{p.a} {sum(1, 2,)} {d.len()} {v.len()} {n} {text}");
    0
}
