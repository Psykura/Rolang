// expect-exit: 99

def main() -> i32 {
    let x: i32? = nil;
    if let v = x { return v; }
    return 99;
}
