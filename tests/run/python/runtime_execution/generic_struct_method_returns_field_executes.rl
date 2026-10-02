// expect-exit: 42

struct GenFieldBox<T> {
    var v: T
    def fetch() -> T { self.v }
}
def main() -> i32 {
    let b = GenFieldBox { v: 42 };
    b.fetch()
}
