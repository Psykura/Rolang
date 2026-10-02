// expect-exit: 42

def main() -> i32 {
    let t = (a: 10, b: 32);
    t.0 + t.1
}
