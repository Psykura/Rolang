protocol Container { associatedtype Item; def first() -> Item; }
protocol Sized: Container { def size() -> i32; }
struct Box: Sized { var v: i32; def first() -> i32 { self.v } def size() -> i32 { 1 } }
def head<C: Container>(c: C) -> C.Item { c.first() }
def describe<S: Sized>(s: S) -> S.Item { if s.size() > 0 { return head(s); } s.first() }
def main() -> i32 { if describe(Box { v: 42 }) == 42 { return 0; } 1 }
