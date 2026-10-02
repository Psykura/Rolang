// expect-error: INVALID_OPERATION: casting to or from RawPtr is unsafe and must be used inside an unsafe block

def main() -> i32 {
    let p: RawPtr = 0 as RawPtr;
    return 0;
}
