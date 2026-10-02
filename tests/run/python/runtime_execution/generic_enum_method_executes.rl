// expect-exit: 42

enum WrapMethod<T> {
    case some(T)
    case none
    def or_default(d: T) -> T {
        switch self {
        case .some(let x): return x;
        case .none: return d;
        }
    }
}
def main() -> i32 {
    let w = WrapMethod.some(42);
    w.or_default(0)
}
