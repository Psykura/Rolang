protocol Source<Output> { def next() -> Output?; }
protocol Container<Item> { def get(index: i32) -> Item; def size() -> i32; }
struct Counter: Source<i32> { var n: i32; def next() -> i32? { if self.n >= 3 { return nil; } self.n += 1; self.n } }
struct Words: Source { var items: [String]; var at: i32 = 0;
    def next() -> String? { if self.at >= self.items.len() { return nil; } self.at += 1; self.items[self.at - 1] } }
struct Stack<T>: Container { var items: [T]; def get(index: i32) -> T { self.items[index] } def size() -> i32 { self.items.len() as i32 } }
def drain<S: Source<i32>>(s: S) -> i32 { var total = 0; while let v = s.next() { total += v; } total }
def first<S: Source>(s: S) -> S.Output? { s.next() }
def last<C: Container<String>>(c: C) -> C.Item { c.get(c.size() - 1) }
def sum(c: any Container<i32>) -> i32 { var total = 0; for i in 0..<c.size() { total += c.get(i); } total }
def main() -> i32 {
    if drain(Counter { n: 0 }) != 6 || first(Words { items: ["x"] }) != "x" { return 1; }
    if last(Stack<String> { items: ["a", "z"] }) != "z" { return 2; }
    let numbers: any Container<i32> = Stack<i32> { items: [40, 2] };
    let texts: [any Container<String>] = [Stack<String> { items: ["ro"] }, Stack<String> { items: ["la", "ng"] }];
    var joined = ""; for c in texts { for i in 0..<c.size() { joined = joined + c.get(i); } }
    let sized: any Container = Stack<Bool> { items: [true, false, true] };
    let source: any Source<i32> = Counter { n: 1 };
    if sum(numbers) != 42 || joined != "rolang" || sized.size() != 3 || source.next() != 2 { return 3; }
    0
}
