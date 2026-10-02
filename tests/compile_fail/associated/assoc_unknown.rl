// expect-error: Generic parameter 'C' has no associated type 'Missing'
protocol Container { associatedtype Item; def first() -> Item; }
def head<C: Container>(c: C) -> C.Missing { c.first() }
def main() -> i32 { 0 }
