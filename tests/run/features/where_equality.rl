protocol Container { associatedtype Item; def first() -> Item; }
struct IntBox: Container { var v: i32; def first() -> i32 { self.v } }
def get<C: Container>(c: C) -> i32 where C.Item == i32 { c.first() }
def main() -> i32 { if get(IntBox { v: 42 }) == 42 { return 0; } 1 }
