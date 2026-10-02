
import "array.rl"
import "test.rl"

def main() -> i32 {
    let arr = [3, 1, 4, 1, 5];

    var r = assert_eq_i32(array_sum(arr), 14);
    if r != 0 { return r; }
    r = assert_true(array_contains(arr, 4));
    if r != 0 { return r; }
    r = assert_false(array_contains(arr, 9));
    if r != 0 { return r; }
    r = assert_eq_i32(array_find(arr, 5), 4);
    if r != 0 { return r; }
    r = assert_eq_i32(array_find(arr, 9), -1);
    if r != 0 { return r; }
    r = assert_eq_i32(array_count(arr, 1), 2);
    if r != 0 { return r; }
    r = assert_eq_i32(array_min(arr) ?? 0, 1);
    if r != 0 { return r; }
    r = assert_eq_i32(array_max(arr) ?? 0, 5);
    if r != 0 { return r; }
    return 0;
}
