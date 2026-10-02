// expect-exit: 42

struct Box { var v: i32? }
def main() -> i32 {
    let b = Box { v: 42 };
    if let x = b.v { return x; }
    return 0;
}
