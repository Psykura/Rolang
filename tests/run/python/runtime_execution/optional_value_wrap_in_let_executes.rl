// expect-exit: 42

def main() -> i32 {
    let x: i32? = 42;
    if let v = x { return v; }
    return 0;
}
