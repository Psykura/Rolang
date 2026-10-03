import std.io
import std.json
extension<T> T? {
    static def nothing() -> T? { nil }
    static def wrap(value: T) -> T? { value }
    def or_else(fallback: T) -> T { if let value = self { return value; } fallback }
}
struct Point { let x: i32; }
def depth<T: Decodable>(text: String) -> String {
    switch T?.from_json(Json.parse(text).ok_value() ?? Json.null()) { case .ok(let value): if let v = value { return "value"; } return "nil"; case .err(let e): return e.to_string(); }
}
def main() -> i32 {
    let a = i32?.nothing();
    let b = String?.wrap("hi");
    let c = Point?.nothing();
    let v = Vec<i32>?.wrap([1, 2]);
    println(f"{a.or_else(-1)} {b.or_else("none")} {c.is_none()} {v.or_else([]).len()}");
    let nested: i32?? = nil;
    let inner: i32?? = a;
    let deep: Vec<String??> = [nil];
    println(f"{nested.is_none()} {inner.is_some()} {deep.len()}");
    let fallback = (b as String? ?? "x");
    println(fallback);
    println(f"{depth<i32>("null")} {depth<i32>("3")} {depth<i32>("\"s\"")}");
    0
}
