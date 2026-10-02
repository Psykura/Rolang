
struct State { var calls: i32; var cleanup: i32; }
def read(s: State) -> i32? {
    s.calls = s.calls + 1;
    if s.calls == 1 { return 42; }
    return nil;
}
def text(s: State) -> String? {
    defer { s.cleanup = s.cleanup + 1; }
    let n = read(s)?;
    return n.to_string();
}
enum Inner { case number(i32); }
enum Outer { case empty; case nested(Inner); }
def classify(value: Outer) -> i32 {
    switch value {
        case .nested(.number(7)): return 7;
        case .nested(.number(let n)) where n > 0: return n;
        default: return 0;
    }
}
def main() -> i32 {
    let s = State { calls: 0, cleanup: 0 };
    if !(text(s) ?? "").equals("42") { return 1; }
    if let value = text(s) { return 2; }
    if s.calls != 2 || s.cleanup != 2 { return 3; }
    if classify(Outer.empty) != 0 { return 4; }
    if classify(Outer.nested(Inner.number(9))) != 9 { return 5; }
    if classify(Outer.nested(Inner.number(7))) != 7 { return 6; }
    return 0;
}
