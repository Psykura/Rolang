import std.io
struct Handler { var on_event: ((String) -> i32)?; }
def main() -> i32 {
    let none: ((i32) -> i32)? = nil;
    let some: ((i32) -> i32)? = (n: i32) -> { n * 10 };
    if let f = some { println(f"bound {f(2)}"); }
    println(f"{none == nil} {some != nil} {none?(1) == nil} {some?(4) ?? -1}");
    let fallback = none ?? (n: i32) -> { n + 100 };
    var later: ((i32) -> i32)? = nil;
    later = (n: i32) -> { n * 2 };
    println(f"{fallback(1)} {(later ?? (n: i32) -> { 0 })(21)}");
    let h = Handler { on_event: (text: String) -> { text.len() as i32 } };
    let empty = Handler { on_event: nil };
    println(f"{h.on_event?("abc") ?? -1} {empty.on_event?("x") ?? -1}");
    let flag = true;
    println(f"{flag ? (1) : (2)}");
    0
}
