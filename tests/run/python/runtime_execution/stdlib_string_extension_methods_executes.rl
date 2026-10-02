
extension String {
    def len() -> i64 {
        unsafe { return rt_string_len(self); }
    }
    def ends_with(suffix: String) -> Bool {
        unsafe { return rt_string_ends_with(self, suffix) != 0; }
    }
    def starts_with(prefix: String) -> Bool {
        unsafe { return rt_string_starts_with(self, prefix) != 0; }
    }
    def contains(needle: String) -> Bool {
        unsafe { return rt_string_contains(self, needle) != 0; }
    }
    def is_empty() -> Bool {
        unsafe { return rt_string_is_empty(self) != 0; }
    }
}

extern "C" def rt_string_len(s: String) -> i64;
extern "C" def rt_string_is_empty(s: String) -> i64;
extern "C" def rt_string_contains(haystack: String, needle: String) -> i32;
extern "C" def rt_string_starts_with(s: String, prefix: String) -> i32;
extern "C" def rt_string_ends_with(s: String, suffix: String) -> i32;

import "test.rl"

def main() -> i32 {
    var s = "hello.rl";

    var r = assert_eq_i64(s.len(), 8);
    if r != 0 { return r; }
    r = assert_true(s.ends_with(".rl"));
    if r != 0 { return r; }
    r = assert_true(s.starts_with("hello"));
    if r != 0 { return r; }
    r = assert_true(s.contains("llo"));
    if r != 0 { return r; }
    r = assert_false(s.is_empty());
    if r != 0 { return r; }
    r = assert_true("".is_empty());
    if r != 0 { return r; }
    return 0;
}
