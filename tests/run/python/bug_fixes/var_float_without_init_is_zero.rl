// expect-exit: 7

def main() -> i32 {
    var f: f64;
    if f == 0.0 { return 7; }
    return 99;
}
