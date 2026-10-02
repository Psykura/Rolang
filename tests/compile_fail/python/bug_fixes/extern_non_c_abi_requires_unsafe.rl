// expect-error: INVALID_OPERATION: calling external 'rust' function is unsafe and must be used inside an unsafe block

extern "rust" def some_fn() -> i32;

def main() -> i32 {
    return some_fn();
}
