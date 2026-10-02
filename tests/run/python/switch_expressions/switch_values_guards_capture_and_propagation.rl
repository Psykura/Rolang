
import std.result
enum Token { case number(i32); case end; }
struct State { var count: i32; }
def next(s: State) -> Token { s.count = s.count + 1; return Token.number(42); }
def fail() -> Result<String, String> { return Result.err(error: "bad"); }
def render(t: Token) -> Result<String, String> {
    let text = switch t { case .number(let n): f"{n}"; case .end: fail()?; };
    return Result.ok(value: text);
}
def choose<T>(flag: Bool, a: T, b: T) -> T { return switch flag { case true: a; case false: b; }; }
def main() -> i32 {
    let s = State { count: 0 };
    let n = switch next(s) { case .number(let v) where v < 0: 0; case .number(let v): v; case .end: 99; };
    if n != 42 || s.count != 1 { return 1; }
    let prefix = "value=";
    let callback: (Token) -> String = (token) -> { switch token { case .number(let value): prefix + f"{value}"; case .end: "end"; } };
    if !callback(Token.number(42)).equals("value=42") { return 2; }
    if !choose(false, "a", "b").equals("b") { return 3; }
    switch render(Token.end) { case .ok(let v): return 4; case .err(let e): if !e.equals("bad") { return 5; } }
    return 0;
}
