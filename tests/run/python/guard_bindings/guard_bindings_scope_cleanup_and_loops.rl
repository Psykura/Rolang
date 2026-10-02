
struct State { var reads: i32; var cleanup: i32; }
def read(s: State) -> i32? { s.reads = s.reads + 1; if s.reads == 1 { return 42; } return nil; }
def render(s: State) -> String? {
    defer { s.cleanup = s.cleanup + 1; }
    guard let n = read(s) else { return nil; }
    return f"{n}";
}
def main() -> i32 {
    let s = State { reads: 0, cleanup: 0 };
    if !(render(s) ?? "").equals("42") { return 1; }
    if let unexpected = render(s) { return 2; }
    if s.reads != 2 || s.cleanup != 2 { return 3; }
    let items = Vec<i32?>.new(); items.push(nil); items.push(42);
    var sum = 0;
    for item in items { guard let n = item else { continue; } sum = sum + n; }
    return sum - 42;
}
