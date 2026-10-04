// expect-error: Type 'Report' does not conform to protocol 'Sendable'
import std.parallel
struct Report { let text: String; }
parallel def work(count: i32) async -> Report { Report { text: "x" } }
def main() async -> i32 { let r = await work(1); 0 }
