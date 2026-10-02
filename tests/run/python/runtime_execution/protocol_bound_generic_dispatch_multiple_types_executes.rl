// expect-exit: 182

protocol HasValue {
    def value() -> i32;
}

struct A { var v: i32; def value() -> i32 { self.v } }
struct B { var w: i32; def value() -> i32 { self.w * 10 } }

def double<T: HasValue>(item: T) -> i32 {
    item.value() * 2
}

def main() -> i32 {
    let a = A { v: 21 };
    let b = B { w: 7 };
    double(a) + double(b)
}
