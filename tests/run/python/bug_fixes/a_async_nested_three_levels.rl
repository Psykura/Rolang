// expect-exit: 22

def leaf() async -> i64 { return 10; }
def deep() async -> i64 {
    let a = await leaf();
    return a + 1;          // 11
}
def mid() async -> i64 {
    let b = await deep();
    return b * 2;          // 22
}
def main() async -> i32 {
    let v = await mid();
    return v as i32;       // 22
}
