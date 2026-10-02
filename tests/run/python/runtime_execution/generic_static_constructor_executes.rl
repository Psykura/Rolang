// expect-exit: 42

struct Box<T> {
    var value: T;

    static def new(value: T) -> Box<T> {
        return Box { value: value };
    }
}

def main() -> i32 {
    let b: Box<i32> = Box.new(42);
    return b.value;
}
