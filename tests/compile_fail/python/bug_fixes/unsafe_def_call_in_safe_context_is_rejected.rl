// expect-error: calling `unsafe def danger` is unsafe and must be used inside an unsafe block

unsafe def danger() -> i32 { return 42; }

def main() -> i32 {
    return danger();
}
