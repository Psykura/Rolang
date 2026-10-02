// expect-exit: 42

def main() -> i32 {
    let t = (10, 20, 12);
    t.0 + t.1 + t.2
}
