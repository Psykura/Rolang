// expect-exit: 42

def main() -> i32 {
    var x: i32? = nil;
    x = 42;
    if let v = x { return v; }
    return 0;
}
