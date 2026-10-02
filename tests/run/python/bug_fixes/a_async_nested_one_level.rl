// expect-exit: 5

def leaf() async -> i32 { return 5; }
def mid() async -> i32 {
    let x = await leaf();
    return x;
}
def main() async -> i32 {
    return await mid();
}
