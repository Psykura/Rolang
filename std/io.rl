// Standard library: I/O operations
//
// Console output of strings; format other values with interpolation, e.g.
// println(f"count={count}").

import "string.rl"

pub extern "C" def rt_io_print_str(s: String) -> Void;
pub extern "C" def rt_io_println_str(s: String) -> Void;
pub extern "C" def rt_io_eprintln_str(s: String) -> Void;
pub extern "C" def rt_io_eprint_str(s: String) -> Void;
pub extern "C" def rt_io_is_terminal(fd: i32) -> i32;

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

pub def eprint(s: String) -> Void {
    unsafe { rt_io_eprint_str(s); }
}

// Whether standard output (fd 1) or standard error (fd 2) is a terminal.
pub def stdout_is_terminal() -> Bool {
    unsafe { return rt_io_is_terminal(1) != 0; }
}
pub def stderr_is_terminal() -> Bool {
    unsafe { return rt_io_is_terminal(2) != 0; }
}
