// expect-error: Type G does not support subscript assignment; define __set__
struct G { var v: i32; def __get__(i: i32) -> i32 { self.v } }
def main() -> i32 { let g = G { v: 1 }; g[0] = 3; 0 }
