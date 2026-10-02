// expect-error: Call to 'doubled' requires C.Item == i32, but it is String
protocol Container { associatedtype Item; def first() -> Item; }
struct Names: Container { var v: String; def first() -> String { self.v } }
def doubled<C: Container>(c: C) -> i32 where C.Item == i32 { c.first() * 2 }
def main() -> i32 { doubled(Names { v: "x" }) }
