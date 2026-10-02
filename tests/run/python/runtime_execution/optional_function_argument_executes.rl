// expect-exit: 42

def take(x: i32?) -> i32 {
    if let v = x { return v; }
    return 0;
}
def main() -> i32 {
    take(42)
}
