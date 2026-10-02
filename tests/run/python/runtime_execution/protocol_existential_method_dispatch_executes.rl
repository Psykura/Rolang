// expect-exit: 42

protocol RuntimeValued {
    def value() -> i32;
}

struct RuntimeValuedBox {
    def value() -> i32 {
        return 42;
    }
}

def main() -> i32 {
    let p: any RuntimeValued = RuntimeValuedBox {};
    return p.value();
}
