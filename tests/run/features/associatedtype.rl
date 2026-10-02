protocol Container { associatedtype Item; def first() -> Item; }
struct IntBox: Container { var v: i32; def first() -> i32 { self.v } }
def get<C: Container>(c: C) -> C.Item { c.first() }
def main() -> i32 { if get(IntBox { v: 42 }) == 42 { return 0; } 1 }
