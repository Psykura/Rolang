// expect-exit: 42

enum Either {
    case left(i32)
    case right
}

def main() -> i32 {
    let x = Either.left(42);
    switch x {
    case .left(let v): return v;
    case .right: return 0;
    }
}
