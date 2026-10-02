protocol Mapper { def apply<U>(f: (i32) -> U) -> U; def pair<A, B>(a: A, b: B) -> (A, B); }
struct W { var v: i32; }
extension W: Mapper { def apply<R>(f: (i32) -> R) -> R { f(self.v) } def pair<X, Y>(a: X, b: Y) -> (X, Y) { (a, b) } }
def use<M: Mapper>(m: M) -> i32 { m.apply((x) -> { x * 2 }) }
def main() -> i32 { let w = W { v: 21 }; if use(w) == 42 && w.pair(40, 2).0 + w.pair(1, 2).1 == 42 { return 0; } 1 }
