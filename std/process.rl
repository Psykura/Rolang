// Standard library: process, environment, arguments
import "string.rl"
import "vec.rl"
import "range.rl"

pub extern "C" def rt_args_count() -> i32;
pub extern "C" def rt_args_get_handle(index: i32) -> RawPtr;
pub extern "C" def rt_env_get_handle(name: String) -> RawPtr;
pub extern "C" def rt_env_set_string(name: String, value: String) -> i32;
pub extern "C" def rt_process_system_string(cmd: String) -> i32;
pub extern "C" def rt_process_run_argv(args: RawPtr) -> i32;
pub extern "C" def rt_process_run_argv_log(args: RawPtr, log: String) -> i32;
pub extern "C" def rt_process_start_argv_log(args: RawPtr, log: String) -> i64;
pub extern "C" def rt_process_wait_started(pid: i64) -> i32;
pub extern "C" def rt_process_cpu_count() -> i32;
pub extern "C" def rt_process_executable_handle() -> RawPtr;
pub extern "C" def rt_process_host_target_handle() -> RawPtr;
pub extern "C" def rt_exit(code: i32) -> Void;
pub extern "C" def rt_stdin_read_line_handle() -> RawPtr;
pub extern "C" def rt_stdin_read_all_handle() -> RawPtr;

pub def argc() -> i32 {
    unsafe { return rt_args_count(); }
}

pub def argv(index: i32) -> String {
    unsafe { return String.from_handle(rt_args_get_handle(index)); }
}

// The command-line arguments after the program name.
pub def arguments() -> Vec<String> {
    let values = Vec<String>.new();
    for index in 1..<argc() { values.push(argv(index)); }
    values
}

pub def env_get(name: String) -> String {
    unsafe { return String.from_handle(rt_env_get_handle(name)); }
}

pub def try_env_get(name: String) -> String? {
    unsafe {
        let handle = rt_env_get_handle(name);
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}

pub def env_set(name: String, value: String) -> i32 {
    unsafe { return rt_env_set_string(name, value); }
}

pub def shell(cmd: String) -> i32 {
    unsafe { return rt_process_system_string(cmd); }
}

pub def run_argv(args: Vec<String>) -> i32 {
    if args.len() == 0 { return -1; }
    unsafe { return rt_process_run_argv(args.raw_handle()); }
}

// Capture both output streams in a file; execution still uses argv directly.
pub def run_argv_log(args: Vec<String>, log: String) -> i32 {
    if args.len() == 0 { return -1; }
    unsafe { return rt_process_run_argv_log(args.raw_handle(), log); }
}
// Starts a program like run_argv_log without waiting: its process id, or -1.
pub def start_argv_log(args: Vec<String>, log: String) -> i64 {
    if args.len() == 0 { return -1; }
    unsafe { return rt_process_start_argv_log(args.raw_handle(), log); }
}
// Waits for a program start_argv_log started: its exit code, or -1.
pub def wait_started(pid: i64) -> i32 { unsafe { return rt_process_wait_started(pid); } }
// Processors available to this process.
pub def cpu_count() -> i32 { unsafe { return rt_process_cpu_count(); } }
pub def executable_path() -> String? {
    unsafe {
        let handle = rt_process_executable_handle();
        if (handle as i64) == 0 { return nil; }
        return String.from_handle(handle);
    }
}
// Version-independent host ABI triple, available without launching clang.
pub def host_target() -> String {
    unsafe { return String.from_handle(rt_process_host_target_handle()); }
}

pub def process_exit(code: i32) -> Void {
    unsafe { rt_exit(code); }
}

pub def stdin_read_line() -> String {
    unsafe { return String.from_handle(rt_stdin_read_line_handle()); }
}

pub def stdin_read_all() -> String {
    unsafe { return String.from_handle(rt_stdin_read_all_handle()); }
}
