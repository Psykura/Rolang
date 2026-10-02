// expect-exit: 16

def main() -> i32 {
    let x: i32 = 1;
    let s: i32 = 100;
    let r = x << s;  // 100 & 31 = 4, so r = 16
    return r;
}
