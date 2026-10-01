import std.iterator

def main() -> i32 {
    let values = [1, 2, 3, 4];
    let (base, _) = (30, 99);
    let selected = values.iter().filter({ n in n > 1 }).map({ n in n * 2 }).collect();
    let first = selected[0..<2];
    var sum = base;
    for value in first { sum += value; }
    let counts = ["answer": sum + 2];
    if (counts["answer"] ?? 0) == 42 { return 0; }
    1
}
