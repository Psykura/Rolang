// expect-exit: 42

protocol Show {
    def show() -> i32;
}

struct A {
    var v: i32
    def show() -> i32 { self.v }
}

def call_show<T: Show>(item: T) -> i32 {
    item.show()
}

def main() -> i32 {
    let a = A { v: 42 };
    call_show(a)
}
