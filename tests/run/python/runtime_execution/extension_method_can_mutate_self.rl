// expect-exit: 10

struct RuntimePoint {
    var x: i64;
    var y: i64;
}

extension RuntimePoint {
    def add(other: RuntimePoint) -> Void {
        self.x = self.x + other.x;
        self.y = self.y + other.y;
    }
}

def main() -> i32 {
    var p1 = RuntimePoint { x: 3, y: 4 };
    let p2 = RuntimePoint { x: 1, y: 2 };
    p1.add(p2);
    return (p1.x + p1.y) as i32;
}
