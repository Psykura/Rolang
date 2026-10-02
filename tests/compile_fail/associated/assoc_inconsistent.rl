// expect-error: Type Bad does not conform to Pair; Method 'right' return type mismatch: expected Item, got Stri
protocol Pair { associatedtype Item; def left() -> Item; def right() -> Item; }
struct Bad: Pair { var n: i32; def left() -> i32 { self.n } def right() -> String { "x" } }
def main() -> i32 { 0 }
