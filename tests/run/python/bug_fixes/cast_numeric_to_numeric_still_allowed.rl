// expect-exit: 30

def main() -> i32 {
    let a: i64 = 30;
    let b: i32 = a as i32;
    let c: f64 = b as f64;
    let d: i32 = c as i32;
    return d;
}
