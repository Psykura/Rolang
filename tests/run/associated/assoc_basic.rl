protocol Container { associatedtype Item; def first() -> Item; def count() -> i32; }
struct IntBox: Container { var v: i32; def first() -> i32 { self.v } def count() -> i32 { 1 } }
struct Names: Container { var names: [String]; def first() -> String { self.names[0] } def count() -> i32 { self.names.len() as i32 } }
def head<C: Container>(c: C) -> C.Item { c.first() }
def main() -> i32 {
    let n = head(IntBox { v: 42 });
    let s = head(Names { names: ["ro", "lang"] });
    if n == 42 && s == "ro" { return 0; }
    1
}
