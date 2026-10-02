// Standard library: I/O operations
//
// Console output of strings; format other values with interpolation, e.g.
// println(f"count={count}").

import "string.rl"

pub extern "C" def rt_io_print_str(s: String) -> Void;
pub extern "C" def rt_io_println_str(s: String) -> Void;
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
