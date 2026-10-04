// expect-error: Type 'Handle' does not conform to protocol 'Sendable'
import std.parallel
struct Handle { let id: i32; }
struct Job: Sendable { let name: String; let handle: Handle; }
def main() -> i32 { 0 }
