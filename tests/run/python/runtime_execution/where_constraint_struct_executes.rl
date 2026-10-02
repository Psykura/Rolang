// expect-exit: 42

protocol Show { def show() -> i32; }
struct A { var v: i32; def show() -> i32 { self.v } }

struct Container<T> where T: Show {
    var item: T;
    def get_show() -> i32 { return self.item.show(); }
}

def main() -> i32 {
    let c = Container<A> { item: A { v: 42 } };
    return c.get_show();
}
