import std.io
def main() -> i32 {
    let a = r#"say "hi""#;
    let b = r##"a "# inside"##;
    let c = r#"C:\path\"quoted"\"#;
    let d = r"plain\n";
    println(a); println(b); println(c); println(d);
    println(f"{a.len()} {b.len()}");
    0
}
