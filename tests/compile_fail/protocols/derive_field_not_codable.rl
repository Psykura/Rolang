// expect-error: Type 'Handler' does not conform to protocol 'Decodable'
import std.json
struct Handler { let name: String; }
struct Config: Codable { let port: i32; let handler: Handler; }
def main() -> i32 { 0 }
