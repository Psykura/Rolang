// expect-error: parallel function 'work' cannot be generic
import std.parallel
parallel def work<T: Sendable>(value: T) async -> T { value }
def main() -> i32 { 0 }
