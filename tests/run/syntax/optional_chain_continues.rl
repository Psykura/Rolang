import std.io
struct Inner { var name: String; var tags: Vec<String>; def shout() -> String { self.name.uppercased() } }
struct Outer { var inner: Inner?; var label: String; }
def main() -> i32 {
    let some: Outer? = Outer { inner: Inner { name: "ro", tags: ["a", "b"] }, label: "  lang  " };
    let none: Outer? = nil;
    println(f"{some?.label.trim() ?? "-"} {none?.label.trim() ?? "-"}");
    println(f"{some?.label.trim().len() ?? -1} {none?.label.len() ?? -1}");
    println(f"{some?.inner?.name.uppercased() ?? "-"} {some?.inner?.shout().len() ?? -1}");
    println(f"{some?.inner?.tags[1] ?? "-"} {some?.inner?.tags.len() ?? -1} {none?.inner?.tags[0] ?? "-"}");
    let text: String? = "a,b,c";
    println(f"{text?.split(",").len() ?? 0} {text?.split(",")[2] ?? "-"}");
    0
}
