// expect-exit: 42

struct Point {
    var x: i32;
    var y: i32;
}

extension Point {
    pub def __add__(other: Point) -> Point {
        return Point { x: self.x + other.x, y: self.y + other.y };
    }
}

def main() -> i32 {
    let p1 = Point { x: 10, y: 20 };
    let p2 = Point { x: 5, y: 7 };
    let p3 = p1 + p2;
    return p3.x + p3.y;
}
