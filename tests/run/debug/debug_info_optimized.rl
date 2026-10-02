// compile-flags: -g -O2
// Debug information covers closures, generics, methods, enums and async code.
import std.task

struct Counter {
    var count: i32;
    def bump(by: i32 = 1) -> i32 { self.count += by; self.count }
}

enum Shape { case circle(f64); case square(f64); }

def area(shape: Shape) -> f64 {
    switch shape {
        case .circle(let r): 3.0 * r * r;
        case .square(let side): side * side;
    }
}

def first<T>(values: Vec<T>, fallback: T) -> T {
    if values.len() == 0 { return fallback; }
    values[0]
}

def double_later(n: i32) async -> i32 {
    await yield_now();
    n * 2
}

def main() async -> i32 {
    let counter = Counter { count: 0 };
    counter.bump();
    counter.bump(by: 2);
    let add = (a: i32, b: i32) -> i32 { a + b };
    let total = add(counter.count, first([9, 4], 0));
    let shapes = [Shape.circle(1.0), Shape.square(2.0)];
    var sum = 0.0;
    for shape in shapes { sum += area(shape); }
    let doubled = await double_later(21);
    if total != 12 || sum != 7.0 || doubled != 42 { return 1; }
    0
}
