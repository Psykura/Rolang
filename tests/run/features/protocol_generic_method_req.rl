protocol Mapper { def apply<U>(f: (i32) -> U) -> U; }
struct W { var v: i32; }
extension W: Mapper { def apply<U>(f: (i32) -> U) -> U { f(self.v) } }
def main() -> i32 { if W { v: 21 }.apply((x) -> { x * 2 }) == 42 { return 0; } 1 }
