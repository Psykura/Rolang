def apply(f: ((i32, i32)) -> i32) -> i32 { f((40, 2)) }
def main() -> i32 {
    let typed = ((a, b): (i32, i32)) -> { a + b };
    let nested = (((a, b), c): ((i32, i32), i32)) -> { a + b + c };
    let pairs: [(i32, String)] = [(1, "a"), (2, "bb")];
    var total = 0;
    for pair in pairs { total += ((n, s): (i32, String)) -> { n + (s.len() as i32) }(pair); }
    let arrow = ((a, b): (i32, i32)) -> i32 { a * b };
    if apply(((a, b)) -> { a + b }) == 42 && typed((40, 2)) == 42 && nested(((40, 1), 1)) == 42 && total == 6 && arrow((6, 7)) == 42 { return 0; }
    1
}
