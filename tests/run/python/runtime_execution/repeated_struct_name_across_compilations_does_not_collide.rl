// expect-exit: 42

struct CollideBox { var first: i64; var second: i64 }
def main() -> i32 {
    let b = CollideBox { first: 10, second: 32 };
    (b.first + b.second) as i32
}
