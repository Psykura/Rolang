
struct Node { var n: i32; }
struct Counter { var n: i32; }
def nested(c: Counter) -> ((i32, String), i32) { c.n = c.n + 1; return ((42, "nested"), 3); }
def pair() -> (i32, String) { return (42, "answer"); }
def main() -> i32 {
    let c = Counter { n: 0 };
    var ((a, text), _) = nested(c);
    a = a + 1;
    let capture: () -> String = () -> { text };
    if c.n != 1 || a != 43 || !capture().equals("nested") { return 11; }
    let (n, name) = pair();
    if n != 42 || !name.equals("answer") { return 1; }
    let pairs = Vec<(i32, String)>.new(); pairs.push(pair());
    for (number, label) in pairs { if number != 42 || !label.equals(name) { return 2; } }
    let values = Vec<Node>.new();
    for i in 0..<4 { values.push(Node { n: i }); }
    let selected = values[1..<3];
    if selected.len() != 2 || selected.get(0).n != 1 { return 3; }
    selected.set(0, Node { n: 99 });
    if values.get(1).n != 1 { return 4; }
    let shared = selected.get(1); shared.n = 9;
    if values.get(2).n != 9 { return 5; }
    if values[-5...99].len() != 4 || values[3..<1].len() != 0 { return 6; }
    if !"猫abc"[3..<5].equals("ab") { return 7; }
    if !"a\0b"[1...2].equals("\0b") { return 8; }
    var count = 0;
    let range = 2147483646...2147483647;
    for i in range { count = count + 1; }
    for i in range { count = count + 1; }
    if count != 4 { return 9; }
    for i in 4..<0 { return 10; }
    return 0;
}
