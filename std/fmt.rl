// Standard library: string formatting
import "string.rl"

pub extern "C" def rt_format_int_handle(fmt: String, val: i32) -> RawPtr;
pub extern "C" def rt_format_i64_handle(fmt: String, val: i64) -> RawPtr;
pub extern "C" def rt_format_f64_handle(fmt: String, val: f64) -> RawPtr;
pub extern "C" def rt_format_bool_handle(fmt: String, val: i32) -> RawPtr;
pub extern "C" def rt_format_str_handle(fmt: String, val: String) -> RawPtr;
pub extern "C" def rt_io_println_str(s: String) -> Void;

pub extension String {
    pub def with_i32(value: i32) -> String {
        unsafe { return String.from_handle(rt_format_int_handle(self, value)); }
    }
    pub def with_i64(value: i64) -> String {
        unsafe { return String.from_handle(rt_format_i64_handle(self, value)); }
    }
    pub def with_f64(value: f64) -> String {
        unsafe { return String.from_handle(rt_format_f64_handle(self, value)); }
    }
    pub def with_bool(value: Bool) -> String {
        unsafe {
            if value { return String.from_handle(rt_format_bool_handle(self, 1)); }
            return String.from_handle(rt_format_bool_handle(self, 0));
        }
    }
    pub def with_str(value: String) -> String {
        unsafe { return String.from_handle(rt_format_str_handle(self, value)); }
    }
}

pub def format_i32(fmt: String, val: i32) -> String {
    unsafe { return String.from_handle(rt_format_int_handle(fmt, val)); }
}
pub def format_i64(fmt: String, val: i64) -> String {
    unsafe { return String.from_handle(rt_format_i64_handle(fmt, val)); }
}
pub def format_f64(fmt: String, val: f64) -> String {
    unsafe { return String.from_handle(rt_format_f64_handle(fmt, val)); }
}
pub def format_bool(fmt: String, val: Bool) -> String {
    unsafe {
        if val { return String.from_handle(rt_format_bool_handle(fmt, 1)); }
        return String.from_handle(rt_format_bool_handle(fmt, 0));
    }
}
pub def format_str(fmt: String, val: String) -> String {
    unsafe { return String.from_handle(rt_format_str_handle(fmt, val)); }
}

pub def println_fmt_i32(fmt: String, val: i32) -> Void {
    unsafe {
        let s = String.from_handle(rt_format_int_handle(fmt, val));
        rt_io_println_str(s);
    }
}
pub def println_fmt_i64(fmt: String, val: i64) -> Void {
    unsafe {
        let s = String.from_handle(rt_format_i64_handle(fmt, val));
        rt_io_println_str(s);
    }
}
pub def println_fmt_str(fmt: String, val: String) -> Void {
    unsafe {
        let s = String.from_handle(rt_format_str_handle(fmt, val));
        rt_io_println_str(s);
    }
}
