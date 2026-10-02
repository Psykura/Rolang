def main() -> i32 {
    var s: String;
    var count: i32;
    let set = () -> { s = "hi"; count = 40; };
    set();
    var (a, b) = (1, 1);
    let bump = () -> { a += 1; };
    bump();
    b = 40;
    let sum = () -> { a + b };
    if s == "hi" && count + a == 42 && sum() == 42 { return 0; }
    1
}
