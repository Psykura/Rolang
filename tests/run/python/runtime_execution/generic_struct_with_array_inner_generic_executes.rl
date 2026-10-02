// expect-exit: 42

struct InnerAG<T> { var v: T }
struct OuterAG<T> {
    var items: [InnerAG<T>]
    def first_v() -> T { self.items[0].v }
}
def main() -> i32 {
    let o = OuterAG<i32> { items: [InnerAG { v: 42 }] };
    o.first_v()
}
