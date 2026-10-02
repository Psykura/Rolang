// expect-exit: 42

enum CtorRes<T, E> {
    case ok(value: T)
    case err(error: E)
}

def make() -> CtorRes<i32, i32> {
    return CtorRes.ok(value: 42);
}

def main() -> i32 {
    let r = make();
    switch r {
    case .ok(let v): return v;
    case .err(let _): return -1;
    }
}
