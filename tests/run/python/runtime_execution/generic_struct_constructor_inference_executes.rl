// expect-exit: 42

struct GenBox<T> {
    var v: T
    def get() -> T { self.v }
}

def main() -> i32 {
    let b = GenBox { v: 42 };
    b.get()
}
