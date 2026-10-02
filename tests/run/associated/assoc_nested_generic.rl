protocol Container { associatedtype Item; def first() -> Item; }
struct Box<T>: Container { var v: T; def first() -> T { self.v } }
def head<C: Container>(c: C) -> C.Item { c.first() }
def twice<D: Container>(d: D) -> (D.Item, D.Item) { let x: D.Item = head(d); (x, head(d)) }
def main() -> i32 {
    let pair = twice(Box<i32> { v: 21 });
    let s = twice(Box<String> { v: "ok" });
    if pair.0 + pair.1 == 42 && s.1 == "ok" { return 0; }
    1
}
