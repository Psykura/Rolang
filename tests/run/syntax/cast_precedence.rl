// `as` binds tighter than binary operators and looser than prefix operators.
def main() -> i32 {
    let text = "hello";
    let n = text.len() as i32 + 1;
    if n != 6 { return 1; }
    let x = 3;
    let wide = -x as i64 * 2;
    if wide != -6 { return 2; }
    // A comparison on both sides of `||` is not a generic argument list.
    let line = 4;
    let lines = [1, 2, 3];
    if line < 1 || line > lines.len() { return 0; }
    3
}
