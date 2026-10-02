enum Shape { case point(x: i32, y: i32); case none; }
def main() -> i32 {
    let s = Shape.point(x: 40, y: 2);
    switch s { case .point(let x, let y): if x + y == 42 { return 0; } case .none: return 2; }
    1
}
