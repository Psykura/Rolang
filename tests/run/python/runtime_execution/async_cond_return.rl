// expect-exit: 42

def fetch() async -> i64 { 42 }

def main() async -> i32 {
    let v = await fetch();
    if v > 100 {
        return 1;
    }
    return v as i32;
}
