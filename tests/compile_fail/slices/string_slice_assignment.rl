// expect-error: String slices cannot be assigned; only Vec supports replacing a range
def main() -> i32 { var s = "abc"; s[0..<1] = "x"; 0 }
