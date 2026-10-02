// expect-exit: 42

struct RuntimeBox<T> {
    var value: T;
}

def main() -> i32 {
    let box = RuntimeBox<i32> { value: 42 };
    return box.value;
}
