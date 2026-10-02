import std.iterator
struct C { var n: i32; }
def apply(f: (i32) -> i32, v: i32) -> i32 { f(v) }
def run(f: () -> Void) -> Void { f(); }
def main() -> i32 {
    let doubled = [1, 2, 18].iter().map((x) -> { x * 2 }).collect();
    let big = doubled.iter().filter((x) -> { x > 3 }).collect();
    let inferred = (a: i32, b: i32) -> { a + b };
    let c = C { n: 0 };
    run(() -> { c.n = 40; });
    let multi = (x: i32) -> { let y = x + 1; return y * 2; };
    let pair = ((a, b): (i32, i32)) -> { a + b };
    let pick = (flag: Bool) -> { if flag { 1 } else { 2 } };
    if apply((x) -> { x + 1 }, 41) == 42 && big.len() == 2 && big[1] == 36 && inferred(40, 2) == 42 && c.n == 40
        && multi(20) == 42 && pair((40, 2)) == 42 && pick(false) == 2 { return 0; }
    1
}
