// expect-exit: 42

def identity<T>(x: T) -> T {
    return x;
}

def main() -> i32 {
    let n = identity(40);
    let ok = identity(true);
    if ok {
        return n + 2;
    }
    return 0;
}
