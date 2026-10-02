
import std.string_builder
import std.interner
import std.io
typealias SymbolId = i32;
typealias Names = Vec<String>;
def main() -> i32 {
    let builder = StringBuilder.new();
    let alias = builder;
    if builder.len() != 0 || !builder.to_string().is_empty() { return 1; }
    var i = 0;
    while i < 10000 { alias.append("ab"); i = i + 1; }
    let original = builder.to_string();
    if original.len() != 20000 { return 2; }
    builder.clear();
    builder.append_line("name");
    builder.append_byte(0 as u8);
    builder.append("end");
    let text = builder.to_string();
    if text.len() != 9 || text.byte_at(5) != 0 { return 3; }
    if original.len() != 20000 { return 4; }
    let names = StringInterner.new();
    let first: SymbolId = names.intern("alpha");
    if first != 0 || names.intern("al" + "pha") != first { return 5; }
    if names.intern("beta") != 1 || names.len() != 2 { return 6; }
    if let absent = names.lookup("missing") { return 7; }
    if let absent = names.resolve(-1) { return 8; }
    if let absent = names.resolve(2) { return 9; }
    if let found = names.resolve(first) {
        if !found.equals("alpha") { return 10; }
    } else { return 11; }
    let saved: Names = Vec<String>.new();
    saved.push(original);
    println(saved.len().to_string());
    return 0;
}
