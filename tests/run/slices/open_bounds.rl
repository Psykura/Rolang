def total(v: [i32]) -> i32 { var s = 0; for x in v { s += x; } s }
def main() -> i32 {
    let v = [1, 2, 3, 4, 5];
    if total(v[..<2]) != 3 || total(v[...1]) != 3 || total(v[3...]) != 9 || total(v[...]) != 15 { return 1; }
    if v[10...].len() != 0 || v[..<0].len() != 0 || total(v[1...3]) != 9 { return 2; }
    let s = "rolang";
    if s[..<2] != "ro" || s[2...] != "lang" || s[...] != "rolang" { return 3; }
    var count = 0;
    for i in ..<3 { count += i; }
    if count != 3 { return 4; }
    0
}
