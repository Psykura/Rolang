import std.io
struct Node { let value: i32; let next: Node?; }
def find(values: Dict<String, i32>, a: String, b: String) -> i32 {
    if let x = values[a], let y = values[b], x < y { return y - x; } else if let x = values[a] { return x; } else { return -1; }
}
def tail(values: Dict<String, i32>, a: String) -> i32 {
    if let x = values[a], x > 10 { x } else { 0 }
}
def checked(a: i32?, b: i32?) -> i32 {
    guard let x = a, let y = b, x + y > 0 else { return -1; }
    x * y
}
def main() -> i32 {
    let d = ["a": 3, "b": 10, "c": 20];
    println(f"{find(d, "a", "b")} {find(d, "b", "a")} {find(d, "z", "a")} {tail(d, "c")} {tail(d, "a")}");
    println(f"{checked(2, 5)} {checked(nil, 5)} {checked(-3, 1)}");
    var list: Node? = Node { value: 1, next: Node { value: 2, next: Node { value: 3, next: nil } } };
    var sum = 0;
    while let node = list, node.value < 3 { sum += node.value; list = node.next; }
    println(f"{sum}");
    var n = 0;
    while n < 10, n * n < 20 { n += 1; }
    println(f"{n}");
    let flag = true; let other: i32? = 4;
    if flag, let v = other { println(f"both {v}"); }
    switch 1 { case 1: if let v = other, v > 3 { println("in case"); } default: {} }
    0
}
