// expect-exit: 42

protocol HasSize {
    var size: i32 { get };
}

struct SizedBox {
    var size: i32
}

def get_size<T: HasSize>(x: T) -> i32 {
    x.size
}

def main() -> i32 {
    let b = SizedBox { size: 42 };
    get_size(b)
}
