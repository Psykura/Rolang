// expect-exit: 42

struct Box { var n: i32 }

def leaf() async -> i32 { return 1; }
def read_after_yield(b: Box) async -> i32 {
    let y = await leaf();
    return b.n + y;
}
def main() async -> i32 {
    let b = Box { n: 41 };
    return await read_after_yield(b);
}
