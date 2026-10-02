// expect-error: 'get' cannot be used through any Container
protocol Container<Item> { def get(index: i32) -> Item; def size() -> i32; }
struct Stack: Container { var items: [i32]; def get(index: i32) -> i32 { self.items[index] } def size() -> i32 { 1 } }
def main() -> i32 { let c: any Container = Stack { items: [1] }; c.get(0) }
