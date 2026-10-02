// expect-exit: 42

def take(x: i64?) -> i64 {
    if let v = x { return v; }
    return 0;
}
def main() -> i32 {
    let a: i32 = 42;
    take(a) as i32
}
