// expect-exit: 42

def leaf() async -> i32 { return 1; }
def add_after_yield(x: i32) async -> i32 {
    let y = await leaf();
    return x + y;
}
def main() async -> i32 {
    return await add_after_yield(41);
}
