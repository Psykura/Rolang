// expect-exit: 42

def fetch() async -> i32? {
    return 42;
}

def main() async -> i32 {
    if let v = await fetch() {
        return v;
    }
    return 0;
}
