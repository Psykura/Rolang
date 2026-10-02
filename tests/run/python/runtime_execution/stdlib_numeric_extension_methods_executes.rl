
extension i32 {
    def abs() -> i32 {
        if self < 0 { return -self; }
        return self;
    }
    def min(other: i32) -> i32 {
        if self < other { return self; }
        return other;
    }
    def max(other: i32) -> i32 {
        if self > other { return self; }
        return other;
    }
    def pow(exp: i32) -> i32 {
        var result = 1;
        var e = exp;
        while e > 0 {
            result = result * self;
            e = e - 1;
        }
        return result;
    }
    def is_positive() -> Bool { return self > 0; }
    def is_negative() -> Bool { return self < 0; }
    def is_zero() -> Bool { return self == 0; }
    def clamp(low: i32, high: i32) -> i32 {
        if self < low { return low; }
        if self > high { return high; }
        return self;
    }
}

import "test.rl"

def main() -> i32 {
    var r = assert_eq_i32((-5).abs(), 5);
    if r != 0 { return r; }
    r = assert_eq_i32(3.min(7), 3);
    if r != 0 { return r; }
    r = assert_eq_i32(3.max(7), 7);
    if r != 0 { return r; }
    r = assert_eq_i32(2.pow(4), 16);
    if r != 0 { return r; }
    r = assert_true(5.is_positive());
    if r != 0 { return r; }
    r = assert_true((-3).is_negative());
    if r != 0 { return r; }
    r = assert_true(0.is_zero());
    if r != 0 { return r; }
    r = assert_eq_i32(5.clamp(10, 20), 10);
    if r != 0 { return r; }
    r = assert_eq_i32(15.clamp(10, 20), 15);
    if r != 0 { return r; }
    r = assert_eq_i32(25.clamp(10, 20), 20);
    if r != 0 { return r; }
    return 0;
}
