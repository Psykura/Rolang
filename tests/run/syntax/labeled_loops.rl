import std.io
def main() -> i32 {
    var pairs = 0;
    outer: for i in 0..<5 {
        inner: for j in 0..<5 {
            if j > i { continue outer; }
            if i == 4 { break outer; }
            pairs += 1;
            if j == 2 { continue inner; }
        }
    }
    var n = 0;
    search: while n < 100 {
        n += 1;
        for k in [1, 2, 3] { if n * k == 12 { break search; } }
    }
    var found = 0;
    let rows = [[1, 2], [3, 42], [5, 6]];
    scan: for row in rows { for value in row { if value == 42 { found = value; break scan; } } }
    var count = 0;
    items: while let x = (count < 3 ? count : nil) { count += 1; if x == 1 { continue items; } }
    println(f"{pairs} {n} {found} {count}");
    0
}
