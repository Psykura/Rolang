// expect-exit: 42

struct RuntimeMethodBox<T> {
    var value: T;

    def choose(x: T) -> T {
        return x;
    }
}

def main() -> i32 {
    let box = RuntimeMethodBox<i32> { value: 1 };
    return box.choose(42);
}
