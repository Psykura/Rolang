// expect-error: INVALID_OPERATION: Constant 'A' depends on itself
let A = B + 1;
let B = A + 1;
def main() -> i32 { A }
