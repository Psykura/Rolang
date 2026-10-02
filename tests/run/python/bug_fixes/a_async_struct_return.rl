// expect-exit: 42

struct Point { var x: i64; var y: i64 }
def make() async -> Point { Point { x: 10, y: 32 } }
def main() async -> i32 {
    let p = await make();
    (p.x + p.y) as i32        // 42
}
