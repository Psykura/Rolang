// expect-error: WRONG_ARG_COUNT: __get__ takes 2 index value(s), got 1
struct G { var v: i32; def __get__(r: i32, c: i32) -> i32 { self.v } }
def main() -> i32 { let g = G { v: 1 }; g[1] }
