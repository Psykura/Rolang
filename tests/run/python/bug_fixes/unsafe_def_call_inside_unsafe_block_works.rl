// expect-exit: 42

unsafe def danger() -> i32 { return 42; }

def main() -> i32 {
    unsafe { return danger(); }
}
