protocol Container { associatedtype Item; def first() -> Item; }
struct IntBox: Container { var v: i32; def first() -> i32 { self.v } }
def doubled<C: Container>(c: C) -> i32 where C.Item == i32 { c.first() * 2 }
def sum<A: Container, B: Container>(a: A, b: B) -> i32 where A.Item == i32, B.Item == i32 { a.first() + b.first() }
def main() -> i32 { if doubled(IntBox { v: 21 }) == 42 && sum(IntBox { v: 40 }, IntBox { v: 2 }) == 42 { return 0; } 1 }
