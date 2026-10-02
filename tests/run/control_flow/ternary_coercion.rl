def main() -> i32 {
    let c = true; let small: i32 = 2; let big: i64 = 40;
    let opt: i32? = nil;
    let a = c ? big : small;
    let b: i64? = c ? 5 : nil;
    let d = !c ? opt : 7;
    let e = c ? nil : 3;
    if a == 40 && (b ?? 0) == 5 && (d ?? 0) == 7 && e == nil { return 0; }
    1
}
