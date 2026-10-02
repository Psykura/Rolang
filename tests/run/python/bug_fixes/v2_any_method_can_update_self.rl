// expect-exit: 3

struct Counter {
    var n: i32;

    def bump() -> Void {
        self.n = self.n + 1;
    }
}

def main() -> i32 {
    var c = Counter { n: 0 };
    c.bump();
    c.bump();
    c.bump();
    return c.n;
}
