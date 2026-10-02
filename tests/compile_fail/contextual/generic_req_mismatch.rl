// expect-error: PROTOCOL_NOT_SATISFIED: Type W does not conform to Mapper; Method 'apply' return type mismatch: expected $U, got i32
protocol Mapper { def apply<U>(f: (i32) -> U) -> U; }
struct W { var v: i32; }
extension W: Mapper { def apply<U>(f: (i32) -> U) -> i32 { self.v } }
def use<M: Mapper>(m: M) -> i32 { 0 }
def main() -> i32 { use(W { v: 1 }) }
