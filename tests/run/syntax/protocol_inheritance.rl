protocol Debug: Display, Sized { def debug() -> String; }
protocol Display { def show() -> String; }
protocol Sized { def size() -> i32; }
struct Item: Debug { var n: i32;
    def show() -> String { "item" } def size() -> i32 { self.n } def debug() -> String { "Item(" + self.show() + ")" } }
def describe<T: Debug>(t: T) -> i32 { if t.show() == "item" && t.debug() == "Item(item)" { return t.size(); } 0 }
def only_display<T: Display>(t: T) -> String { t.show() }
def main() -> i32 {
    let any_debug: any Debug = Item { n: 42 };
    if describe(Item { n: 42 }) == 42 && only_display(Item { n: 1 }) == "item" && any_debug.size() == 42 { return 0; }
    1
}
