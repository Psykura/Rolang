protocol Shape { def area() -> i32; }
protocol Named { def name() -> String; }
struct Square: Shape, Named { var side: i32; def area() -> i32 { self.side * self.side } def name() -> String { "square" } }
struct Box<T>: Shape { var item: T; var size: i32; def area() -> i32 { self.size } }
enum Unit: Shape { case one; def area() -> i32 { 1 } }
def total<S: Shape>(s: S) -> i32 { s.area() }
def main() -> i32 {
    let shapes: [any Shape] = [Square { side: 6 }, Box<String> { item: "x", size: 5 }, Unit.one];
    var sum = 0; for s in shapes { sum += s.area(); }
    if sum == 42 && total(Unit.one) == 1 && Square { side: 1 }.name() == "square" { return 0; }
    1
}
