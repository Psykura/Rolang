
struct Elem<T> {
    var value: T;

    static def make(value: T) -> Elem<T> {
        return Elem { value: value };
    }

    static def size_of() -> i32 {
        return size_of(T);
    }
}

def main() -> i32 {
    let a: Elem<String> = Elem.make("hello");
    let s: i32 = Elem<String>.size_of();
    if s != 8 { return s; }
    return 0;
}
