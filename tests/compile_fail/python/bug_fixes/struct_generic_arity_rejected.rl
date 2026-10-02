// expect-error: Struct 'Box' expects 1 generic argument(s), got 2

struct Box<T> { var value: T; }
def main() -> i32 {
    let b = Box<i32, i32> { value: 1 };
    return b.value;
}
