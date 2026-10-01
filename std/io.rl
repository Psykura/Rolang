// Standard library: I/O operations
//
// Underlying C runtime functions (rolang_rt.c):
//   rt_io_print_str(String)    - print string without newline
//   rt_io_println_str(String)  - print string with newline
//   rt_io_print_i32(i32)       - print i32 without newline
//   rt_io_println_i32(i32)     - print i32 with newline
//   rt_print_i64(i64)          - print i64 with newline (built-in)

import "string.rl"

pub extern "C" def rt_io_print_str(s: String) -> Void;
pub extern "C" def rt_io_println_str(s: String) -> Void;
pub extern "C" def rt_io_print_i32(value: i32) -> Void;
pub extern "C" def rt_io_println_i32(value: i32) -> Void;
pub extern "C" def rt_print_i64(value: i64) -> Void;
pub extern "C" def rt_io_eprintln_str(s: String) -> Void;

// ---- String output ----

pub def print(s: String) -> Void {
    unsafe { rt_io_print_str(s); }
}

pub def println(s: String) -> Void {
    unsafe { rt_io_println_str(s); }
}

pub def eprintln(s: String) -> Void {
    unsafe { rt_io_eprintln_str(s); }
}

// ---- Integer output ----

pub def print_i32(value: i32) -> Void {
    unsafe { rt_io_print_i32(value); }
}

pub def println_i32(value: i32) -> Void {
    unsafe { rt_io_println_i32(value); }
}

pub def println_i64(value: i64) -> Void {
    unsafe { rt_print_i64(value); }
}
