struct V { var x: i32;
    def __neg__() -> V { V { x: -self.x } }
    def __pos__() -> V { V { x: self.x + 100 } }
    def __invert__() -> i32 { ~self.x } }
def main() -> i32 {
    let p = +5; let f = +2.5; let v = V { x: 42 };
    if p == 5 && f == 2.5 && (-v).x == -42 && (+v).x == 142 && ~v == -43 { return 0; }
    1
}
