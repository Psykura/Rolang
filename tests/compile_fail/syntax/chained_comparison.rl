// expect-error: comparisons do not chain
def main() -> i32 {
    let a = 1; let b = 2; let c = 3;
    if a < b < c { return 0; }
    1
}
