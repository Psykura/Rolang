// expect-exit: 42

struct GuardBox {
    var v: i32
    def get_pos() -> i32 {
        if self.v > 0 { return self.v; }
        return 0;
    }
}
def main() -> i32 {
    let b = GuardBox { v: 42 };
    b.get_pos()
}
