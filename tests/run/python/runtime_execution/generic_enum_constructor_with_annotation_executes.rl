// expect-exit: 42

enum Opt<T> {
    case none
    case some(T)
}

def main() -> i32 {
    let x: Opt<i32> = Opt.some(42);
    switch x {
    case .none: return 0;
    case .some(let v): return v;
    }
}
