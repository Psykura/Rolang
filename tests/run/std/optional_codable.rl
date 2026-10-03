import std.io
import std.json
extension<T> T? { def or_else(fallback: T) -> T { if let value = self { return value; } fallback } }
struct User: Codable, Equatable { let name: String; let tags: Vec<String?>; let scores: Dict<String, i32?>; let nick: String?; }
def main() -> i32 {
    let scores = Dict<String, i32?>.new(); scores["a"] = 1; scores["b"] = nil;
    let u = User { name: "ro", tags: ["a", nil], scores, nick: nil };
    let text = encode_json(u);
    println(text);
    switch decode_json<User>(text) { case .ok(let back): println(f"{back == u}"); case .err(let e): println(e.to_string()); }
    let n: i32? = nil;
    println(encode_json(n));
    if let a = decode_json<i32?>("null").ok_value() { if let b = decode_json<i32?>("5").ok_value() { println(f"{a.or_else(-1)} {b.or_else(-1)}"); } }
    switch decode_json<Vec<i32?>>("[1, \"x\"]") { case .ok(let v): println("??"); case .err(let e): println(e.to_string()); }
    if let v = decode_json<Vec<i32?>>("[1, null, 3]").ok_value() { println(encode_json(v)); }
    0
}
