protocol Container {
    associatedtype Item;
    def get(index: i32) -> Item;
    def size() -> i32;
}
struct Stack<T>: Container {
    var items: [T];
    def get(index: i32) -> T { self.items[index] }
    def size() -> i32 { self.items.len() as i32 }
}

let FIRST = 0;

def last<C: Container>(c: C) -> C.Item { c.get(c.size() - 1) }
def total<C: Container>(c: C) -> i32 where C.Item == i32 {
    var sum = 0;
    for index in FIRST..<c.size() { sum += c.get(index); }
    sum
}

def main() -> i32 {
    let numbers = Stack<i32> { items: [10, 30, 2] };
    let words = Stack<String> { items: ["ro", "lang"] };
    if total(numbers) == 42 && last(words) == "lang" && last(numbers) == 2 { return 0; }
    1
}
