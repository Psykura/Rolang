protocol Readable { def read() -> i32; }
struct Item { var value: i32; }
extension Item: Readable { def read() -> i32 { self.value } }
struct Box<T> { var value: T; def get() -> T { self.value } }
typealias Wrapped<T> = Box<T>;

def read_static<T: Readable>(value: T) -> i32 { value.read() }
def read_dynamic(value: any Readable) -> i32 { value.read() }

def main() -> i32 {
    let item = Item { value: 42 };
    let boxed = Wrapped<Item> { value: item };
    if read_static(boxed.get()) == 42 && read_dynamic(item) == 42 { return 0; }
    1
}
