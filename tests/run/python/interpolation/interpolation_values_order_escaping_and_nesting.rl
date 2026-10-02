
import std.io
struct State { var n: i32; }
struct Name { var text: String; def to_string() -> String { return self.text; } }
def next(s: State) -> i32 { s.n = s.n + 1; return s.n; }
def main() -> i32 {
    let state = State { n: 0 };
    println(f"  {{{next(state)}}} {next(state)} {next(state)}  ");
    println(f"{true}/{false}: {Name { text: "猫" }} {f"nested {42}"}");
    let max: u64 = 18446744073709551615;
    println(f"{max} {255 as u8} {-7 as i8} {3.5 as f32}");
    println(f"// unchanged text /* yes */\n\"quote\" \\ {{literal}}");
    println("{ordinary}");
    let binary = f"a\0{42}z";
    if binary.len() != 5 || binary.byte_at(1) != 0 { return 1; }
    if !f"".is_empty() { return 2; }
    if state.n != 3 { return 3; }
    return 0;
}
