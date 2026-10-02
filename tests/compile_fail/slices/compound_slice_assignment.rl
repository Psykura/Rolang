// expect-error: compound assignment '+=' to a slice is not supported
def main() -> i32 { var v = [1, 2]; v[0..<1] += [3]; 0 }
