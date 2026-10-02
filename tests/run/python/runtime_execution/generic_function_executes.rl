// expect-exit: 42

def identity<T>(x: T) -> T {
    return x;
}

def main() -> i32 {
    return identity(42);
}
