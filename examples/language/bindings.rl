struct Counter { var value: i32; }

def main() -> i32 {
    let first = Counter { value: 1 };
    let second = first;
    second.value += 1;
    var total = 40;
    total += first.value;
    if total == 42 { return 0; }
    1
}
