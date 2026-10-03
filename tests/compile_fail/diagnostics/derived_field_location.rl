// expect-error: --> derived_field_location.rl:7:5
import std.json
struct Handler { let name: String; }

struct Config: Encodable {
    let port: i32;
    let handler: Handler;
}

def main() -> i32 { 0 }
