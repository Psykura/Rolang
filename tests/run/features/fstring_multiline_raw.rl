def main() -> i32 {
    let v = 42;
    let s = f"""a{v}
b""";
    let r = r"""x\n""";
    if s.equals("a42\nb") && r.len() == 3 { return 0; }
    1
}
