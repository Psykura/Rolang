
enum Parsed<E, T> { case err(error: E); case ok(value: T); }
enum Output { case ok(value: i64); case err(error: String); }
def token(fail: Bool) -> Parsed<String, i32> {
    if fail { return Parsed<String, i32>.err(error: "bad"); }
    return Parsed<String, i32>.ok(value: 42);
}
def parse(fail: Bool) -> Output {
    let n = token(fail)?;
    return Output.ok(value: n as i64);
}
def main() -> i32 {
    switch parse(false) {
        case .ok(let n): if n != 42 { return 1; }
        case .err(let e): return 2;
    }
    switch parse(true) {
        case .ok(let n): return 3;
        case .err(let e): if !e.equals("bad") { return 4; }
    }
    return 0;
}
