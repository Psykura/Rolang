import std.io
import std.result
enum Mode: Equatable { case fast; case slow; case custom(i32); }
struct Config { var mode: Mode; var backup: Mode? = nil; }
def run(mode: Mode) -> String {
    switch mode { case .fast: "fast"; case .slow: "slow"; case .custom(let n): f"custom {n}"; }
}
def pick(flag: Bool) -> Mode { flag ? .fast : .custom(7) }
def parse(text: String) -> Result<i32, String> {
    if text.len() == 0 { return .err(error: "empty"); }
    .ok(value: text.len() as i32)
}
def main() -> i32 {
    let m: Mode = .slow;
    var c = Config { mode: .custom(3) };
    c.backup = .fast;
    c.mode = .fast;
    println(f"{run(m)} {run(.custom(2))} {run(c.mode)} {run(pick(false))}");
    println(f"{m == .slow} {m != .slow} {.fast == c.mode} {c.backup == .fast} {c.mode == .custom(1)}");
    let modes: Vec<Mode> = [.fast, .slow, .custom(9)];
    println(f"{modes.len()} {run(modes[2])}");
    switch parse("abc") { case .ok(let n): println(f"ok {n}"); case .err(let e): println(e); }
    switch parse("") { case .ok(let n): println(f"ok {n}"); case .err(let e): println(e); }
    let maybe: Mode? = .custom(5);
    if let found = maybe { println(run(found)); }
    0
}
