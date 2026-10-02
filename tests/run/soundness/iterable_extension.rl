struct Countdown { var n: i32; }
extension Countdown {
    def __iter__() -> Countdown { self }
    def __next__() -> i32? { if self.n == 0 { return nil; } self.n -= 1; self.n + 1 }
}
def main() -> i32 { var total = 0; for x in Countdown { n: 3 } { total += x; } if total == 6 { return 0; } 1 }
