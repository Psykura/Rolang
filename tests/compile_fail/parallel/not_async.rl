// expect-error: parallel function 'work' must be async
import std.parallel
parallel def work(count: i32) -> i32 { count }
def main() -> i32 { 0 }
