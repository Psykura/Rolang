// Standard library: panic / abort with a custom message.
//
// The runtime already has internal panic helpers used by codegen-emitted
// runtime checks (divide-by-zero, OOB, etc.), but they weren't reachable
// from user Rolang code. `panic(msg)` here closes that gap: any function
// that hits an unrecoverable invariant violation can call it.
//
// All of these are noreturn — the process exits with status 134 (abort).

import "string.rl"

pub extern "C" def rt_panic_msg_string(msg: String) -> Void;

// Abort with a message. Prints "rolang panic: <msg>" to stderr and
// terminates the process.
pub def panic(msg: String) -> Void {
    unsafe { rt_panic_msg_string(msg); }
}

// Sugar for the common "this branch is unreachable" pattern.
pub def unreachable(reason: String) -> Void {
    unsafe { rt_panic_msg_string(reason); }
}
