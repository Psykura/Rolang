struct Box<T> { var v: T; def get() -> T { self.v } def set(x: T) -> Void { self.v = x; } }
def id<T>(t: T) -> T { let x: T = t; x }
def wrap<T>(t: T) -> T? { t }
def first<T>(xs: [T]) -> T { let v: [T] = xs; v[0] }
def main() -> i32 {
    let b = Box<i32> { v: 1 }; b.set(42);
    if id(b.get()) == 42 && (wrap(2) ?? 0) == 2 && first([7]) == 7 { return 0; }
    1
}
