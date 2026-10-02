// expect-exit: 42

def fetch() async -> i64 {
    42
}

def main() async -> i32 {
    let x = await fetch();
    x as i32
}
