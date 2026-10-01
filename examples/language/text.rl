import std.string_builder
import std.interner

def main() -> i32 {
    let path = r"C:\compiler\cache";
    let text = "hé\0llo";
    let builder = StringBuilder.new();
    builder.append(f"{{{42}}}");
    let names = StringInterner.new();
    let first = names.intern("token");
    if names.intern("token") == first && builder.to_string().equals("{42}")
        && text.len() == 7 && text.byte_at(3) == 0 && path.contains(r"\") { return 0; }
    1
}
