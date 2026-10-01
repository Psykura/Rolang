// Standard library: character classification
//
// These functions classify individual byte values (ASCII).
// They operate on i32 (returned by String.char_at() / String.byte_at()).

pub extern "C" def rt_char_is_digit(ch: i32) -> i32;
pub extern "C" def rt_char_is_alpha(ch: i32) -> i32;
pub extern "C" def rt_char_is_alnum(ch: i32) -> i32;
pub extern "C" def rt_char_is_space(ch: i32) -> i32;

// ---- Character classification ----

pub def char_is_digit(ch: i32) -> Bool {
    unsafe { return rt_char_is_digit(ch) != 0; }
}

pub def char_is_alpha(ch: i32) -> Bool {
    unsafe { return rt_char_is_alpha(ch) != 0; }
}

pub def char_is_alnum(ch: i32) -> Bool {
    unsafe { return rt_char_is_alnum(ch) != 0; }
}

pub def char_is_space(ch: i32) -> Bool {
    unsafe { return rt_char_is_space(ch) != 0; }
}

pub def char_is_upper(ch: i32) -> Bool {
    return ch >= 65 && ch <= 90;  // 'A' to 'Z'
}

pub def char_is_lower(ch: i32) -> Bool {
    return ch >= 97 && ch <= 122; // 'a' to 'z'
}

pub def char_to_upper(ch: i32) -> i32 {
    if char_is_lower(ch) {
        return ch - 32;
    }
    return ch;
}

pub def char_to_lower(ch: i32) -> i32 {
    if char_is_upper(ch) {
        return ch + 32;
    }
    return ch;
}

pub def char_is_newline(ch: i32) -> Bool {
    return ch == 10; // '\n'
}

pub def char_is_tab(ch: i32) -> Bool {
    return ch == 9;  // '\t'
}

pub def char_is_underscore(ch: i32) -> Bool {
    return ch == 95; // '_'
}
