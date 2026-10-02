def main() -> i32 {
    let h = 0x2A; let b = 0b10_1010; let o = 0o52; let d = 4_2; let f = 4.2e1; let g = 42e0;
    if h == 42 && b == 42 && o == 42 && d == 42 && f == 42.0 && g == 42.0 { return 0; }
    1
}
