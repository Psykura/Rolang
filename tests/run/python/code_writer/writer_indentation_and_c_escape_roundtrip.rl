
import std.code_writer
import std.io
def main() -> i32 {
    let writer = CodeWriter.with_indent("  ");
    writer.line("#include <stdio.h>");
    writer.line("int main(void) {");
    writer.indent();
    let text = "a\0" + "7f?\"\\\n猫";
    writer.write("const char bytes[] = ");
    writer.write(c_quote(text));
    writer.line(";");
    writer.line("fwrite(bytes, 1, sizeof(bytes) - 1, stdout);\nreturn 0;");
    if !writer.dedent() || writer.dedent() { return 1; }
    writer.line("}");
    let saved = writer.to_string();
    writer.clear();
    writer.indent(); writer.line(""); writer.write("\nx"); writer.write("y");
    if !writer.to_string().equals("\n\n  xy") { return 2; }
    print(saved);
    return 0;
}
