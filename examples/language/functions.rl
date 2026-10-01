def scale(value: i32, factor: i32 = 2) -> i32 { value * factor }

def main() -> i32 {
    let first = scale(21);
    let second = scale(value: 14, factor: 3);
    if first == 42 && second == 42 { return 0; }
    1
}
