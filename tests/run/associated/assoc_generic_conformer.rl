protocol Container { associatedtype Item; def get(i: i32) -> Item; def size() -> i32; }
struct Stack<T>: Container { var items: [T]; def get(i: i32) -> T { self.items[i] } def size() -> i32 { self.items.len() as i32 } }
def last<C: Container>(c: C) -> C.Item { c.get(c.size() - 1) }
def main() -> i32 {
    let ints = Stack<i32> { items: [1, 2, 42] };
    let strs = Stack<String> { items: ["a", "z"] };
    if last(ints) == 42 && last(strs) == "z" { return 0; }
    1
}
