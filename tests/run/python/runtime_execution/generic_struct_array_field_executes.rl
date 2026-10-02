// expect-exit: 42

struct ArrBox<T> {
    var items: [T]
}
def main() -> i32 {
    let b = ArrBox<i32> { items: [10, 20, 12] };
    b.items[0] + b.items[1] + b.items[2]
}
