// expect-error: '==' requires T: Equatable, but P does not conform: missing __eq__
struct P { let x: i32; }
def main() -> i32 { if [P { x: 1 }] == [P { x: 1 }] { return 1; } 0 }
