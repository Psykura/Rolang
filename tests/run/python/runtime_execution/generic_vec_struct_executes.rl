// expect-exit: 30

import "vec.rl"

struct Point {
    var x: i32;
    var y: i32;
}

def main() -> i32 {
    var v: Vec<Point> = Vec<Point>.new();
    let p1 = Point { x: 10, y: 20 };
    let p2 = Point { x: 5, y: 7 };
    v.push(p1);
    v.push(p2);
    let q = v.get(0);
    return q.x + q.y;
}
