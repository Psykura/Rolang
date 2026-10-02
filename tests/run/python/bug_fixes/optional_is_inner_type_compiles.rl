// expect-exit: 7

def main() -> i32 {
    let x: i32? = 1;
    if x is i32 { return 7; }
    return 0;
}
