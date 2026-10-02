
import std.result
typealias ParseResult<T> = Result<T, String>;
typealias Option<T> = T?;
typealias List<T> = Vec<T>;
typealias Callback<T, U> = (T) -> U;
typealias Reversed<A, B> = (B, A);
def first<A, B>(pair: Reversed<A, B>) -> B { return pair.0; }
def run<T, U>(f: Callback<T, U>, value: T) -> U { return f(value); }
typealias Record = Item;
struct Item { var n: i32; static def new(n: i32) -> Record { return Item { n: n }; } }
def parse() -> ParseResult<i32> { return Result.ok(value: 42); }
def text() -> ParseResult<String> { let n = parse()?; return Result.ok(value: f"{n}"); }
def main() -> i32 {
    if first((42, "text")) != 42 { return 7; }
    if !run((n) -> { f"{n}" }, 42).equals("42") { return 8; }
    let list = List<i32>.new(); list.push(42);
    let f: Callback<i32, String> = (x) -> { f"{x}" };
    let value: Option<String> = f(list.get(0));
    if !(value ?? "").equals("42") { return 1; }
    if Item.new(42).n != 42 { return 2; }
    switch text() { case .ok(let s): if !s.equals("42") { return 3; } case .err(let e): return 4; }
    return 0;
}
