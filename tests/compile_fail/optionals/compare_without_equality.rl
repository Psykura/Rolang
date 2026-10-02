// expect-error: Cannot compare Box and Box
struct Box { var v: i32; }
def main() -> i32 { let b: Box? = nil; if b == Box { v: 1 } { return 1; } 0 }
