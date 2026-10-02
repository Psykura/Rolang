// expect-error: TYPE_MISMATCH: Cannot assign i32 to String in Vec element 0
def main() -> i32 { let v: [String] = [1]; let d: [String: i32] = ["a": "b"]; 0 }
