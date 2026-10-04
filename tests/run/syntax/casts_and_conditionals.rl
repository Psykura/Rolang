import std.io
struct P { let x: i32; }
def main() -> i32 {
    let a = 5 as i32?;
    let b = 7 as i64?;
    let p = P { x: 1 } as P?;
    let n: i32? = 3;
    println(f"{a ?? 0} {b ?? 0} {p?.x ?? 0} {(n as i32?) ?? 0}");
    // `as T ? a : b` is a conditional; `as T?` makes an optional where the type ends.
    let items = [10, 20];
    var i = 0;
    var total = 0;
    while let value = (i < items.len() as i32 ? items[i] as i32? : nil) { total += value; i += 1; }
    let flag = 1;
    let wide = flag as Bool ? "yes" : "no";
    println(f"{total} {wide}");
    0
}
