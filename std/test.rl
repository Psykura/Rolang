// Standard library: test assertion helpers
// Use exit codes to signal test results: 0 = pass, non-zero = fail

pub def assert_eq_i32(expected: i32, actual: i32) -> i32 {
    if expected != actual { return 1; }
    return 0;
}

pub def assert_eq_i64(expected: i64, actual: i64) -> i32 {
    if expected != actual { return 1; }
    return 0;
}

pub def assert_true(condition: Bool) -> i32 {
    if condition == false { return 1; }
    return 0;
}

pub def assert_false(condition: Bool) -> i32 {
    if condition == true { return 1; }
    return 0;
}
