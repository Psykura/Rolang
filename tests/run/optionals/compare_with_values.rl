struct Point { var x: i32; var y: i32; def __eq__(other: Point) -> Bool { self.x == other.x && self.y == other.y } }
struct Log { var text: String; }
def lookup(log: Log, key: String) -> i32? { log.text = log.text + key; if key == "a" { return 5; } nil }
def main() -> i32 {
    let some: i32? = 5; let none: i32? = nil; let wide: i64? = 5;
    if !(some == 5) || some != 5 || none == 5 || !(none != 5) { return 1; }
    if !(5 == some) || !(wide == 5) || !(some == wide) { return 2; }
    let name: String? = "ro";
    if !(name == "ro") || name == "x" || !(name != "x") { return 3; }
    let a: i32? = nil; let b: i32? = nil; let c: i32? = 7;
    if !(a == b) || a != b || a == c || !(c != a) || !(c == 7) { return 4; }
    let p: Point? = Point { x: 1, y: 2 };
    if !(p == Point { x: 1, y: 2 }) || p == Point { x: 0, y: 0 } { return 5; }
    // Each operand is evaluated once, left to right.
    let log = Log { text: "" };
    if !(lookup(log, "a") == lookup(log, "a") || true) { return 6; }
    if lookup(log, "b") == lookup(log, "c") { log.text = log.text + "="; }
    if log.text != "aabc=" { return 7; }
    0
}
