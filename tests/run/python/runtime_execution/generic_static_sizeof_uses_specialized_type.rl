
struct Box<T> {
    var elem_size: i32;

    static def new(value: T) -> Box<T> {
        return Box { elem_size: size_of(T) };
    }
}

def main() -> i32 {
    let b: Box<String> = Box.new("hello");
    if b.elem_size != 8 { return b.elem_size; }
    return 0;
}
