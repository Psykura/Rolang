// expect-error: Cannot assign C.Item to i32 in return value
protocol Container { associatedtype Item; def first() -> Item; }
def bad<C: Container>(c: C) -> i32 { c.first() }
def main() -> i32 { 0 }
