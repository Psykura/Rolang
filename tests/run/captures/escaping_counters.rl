def make_counter(start: i32) -> () -> i32 {
    var count = start;
    () -> { count += 1; count }
}
def main() -> i32 {
    let a = make_counter(0); let b = make_counter(40);
    a(); a();
    let third = a();
    let c = b(); let d = b();
    if third == 3 && c == 41 && d == 42 { return 0; }
    1
}
