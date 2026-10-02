// expect-error: TYPE_MISMATCH: Integer literal 9999999999 does not fit in i32

def main() -> i32 {
    let bad: i32 = 9999999999;
    return bad;
}
