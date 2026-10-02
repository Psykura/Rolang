def main() -> i32 {
    var fact: (i32) -> i32 = (n) -> { 0 };
    fact = (n) -> { if n <= 1 { 1 } else { n * fact(n - 1) } };
    if fact(5) == 120 { return 0; }
    1
}
