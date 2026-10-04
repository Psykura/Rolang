// expect-error: Type 'Config' does not conform to protocol 'Sendable'
import std.parallel
struct Config { let name: String; }
parallel def work(config: Config, count: i32) async -> i32 { count }
def main() async -> i32 { await work(Config { name: "x" }, 1) }
