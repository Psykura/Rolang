// expect-exit: 42

def maybe(b: Bool) -> i32? {
    if b { return 42; }
    return nil;
}
def main() -> i32 {
    if let v = maybe(true) { return v; }
    return 0;
}
