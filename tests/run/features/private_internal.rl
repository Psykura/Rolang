private def a() -> i32 { 40 }
internal def b() -> i32 { 2 }
struct S { private var x: i32; internal var y: i32; }
def main() -> i32 { let s = S { x: a(), y: b() }; if s.x + s.y == 42 { return 0; } 1 }
