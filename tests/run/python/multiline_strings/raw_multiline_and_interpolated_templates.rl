
import std.io
def main() -> i32 {
    let raw = r"C:\new\test\";
    if !raw.equals("C:\\new\\test\\") { return 1; }
    let code = """int main(void) {
    return 42;
}
""";
    let value = 42;
    let template = f"""int main(void) {{
    return {value};
}}
""";
    if !code.equals(template) { return 2; }
    let quoted = r""""quote" \n {literal}
line""";
    if !quoted.equals("\"quote\" \\n {literal}\nline") { return 3; }
    if !"""a\0b""".equals("a\0b") { return 4; }
    if !f"""{f"inner {value}"}""".equals("inner 42") { return 5; }
    print(template);
    return 0;
}
