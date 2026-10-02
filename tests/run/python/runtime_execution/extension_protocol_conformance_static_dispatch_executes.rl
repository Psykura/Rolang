// expect-exit: 42

protocol ShowExt {
    def show() -> i32;
}

struct ExtA { var v: i32 }

extension ExtA: ShowExt {
    def show() -> i32 { self.v }
}

def call_show<T: ShowExt>(x: T) -> i32 { x.show() }

def main() -> i32 {
    let a = ExtA { v: 42 };
    call_show(a)
}
