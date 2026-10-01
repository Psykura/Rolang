struct Counter { var value: i32; }

def sum(counter: Counter) -> i32 {
    defer { counter.value += 1; }
    var total = 0;
    for n in 0..<10 {
        if n == 3 { continue; }
        if n == 8 { break; }
        total += n;
    }
    total
}
def main() -> i32 {
    let counter = Counter { value: 0 };
    if sum(counter) == 25 && counter.value == 1 { return 0; }
    1
}
