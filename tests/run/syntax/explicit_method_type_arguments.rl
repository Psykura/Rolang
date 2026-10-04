import std.io
import std.json
struct Store {
    var items: Vec<String>;
    def first<T: Decodable>() -> T? { decode_json<T>(self.items[0]).ok_value() }
    def convert<A, B>(value: A, fallback: B) -> B { fallback }
    static def make<T>(value: T) -> Vec<T> { [value] }
}
struct Box<T> {
    let value: T;
    def map<U>(f: (T) -> U) -> Box<U> { Box<U> { value: f(self.value) } }
    def cast<U>() -> U? { nil }
}
struct P { let x: i32; let y: i32; def f(n: i32) -> i32 { n } }
def both(a: Bool, b: Bool) -> Bool { a && b }
def main() -> i32 {
    let s = Store { items: ["42", "true"] };
    let n = s.first<i32>();
    let x = s.convert<i32, String>(1, "fallback");
    let v = Store.make<String>("hi");
    let b = Box<i32> { value: 3 };
    let m = b.map<String>((n) -> { f"<{n}>" });
    let c = b.cast<Vec<String>>();
    println(f"{n ?? -1} {x} {v.len()} {m.value} {c == nil}");
    // Comparisons that only look like type arguments.
    let p = P { x: 1, y: 5 };
    println(f"{both(p.x < p.y, p.y > p.x)} {p.x < p.f(2)} {p.x < 3 && 4 > p.f(1)}");
    0
}
