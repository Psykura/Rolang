// expect-error: requires T: Encodable, but Handler does not conform
import std.json
struct Handler { let name: String; }
def main() -> i32 {
    let handler: Handler? = nil;
    encode_json(handler);
    0
}
