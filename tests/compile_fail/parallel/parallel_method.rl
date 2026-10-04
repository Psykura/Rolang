// expect-error: parallel functions are top-level functions
import std.parallel
struct S { parallel def work() async -> i32 { 1 } }
def main() -> i32 { 0 }
