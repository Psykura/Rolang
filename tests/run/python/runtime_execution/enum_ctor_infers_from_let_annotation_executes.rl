// expect-exit: 42

enum CtorRes2<T, E> {
    case ok(value: T)
    case err(error: E)
}

def main() -> i32 {
    let r: CtorRes2<i32, i32> = CtorRes2.ok(value: 42);
    switch r {
    case .ok(let v): return v;
    case .err(let _): return -1;
    }
}
