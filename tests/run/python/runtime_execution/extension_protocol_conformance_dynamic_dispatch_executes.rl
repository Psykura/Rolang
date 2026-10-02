// expect-exit: 42

protocol ShowDyn {
    def show() -> i32;
}

struct DynA { var v: i32 }

extension DynA: ShowDyn {
    def show() -> i32 { self.v }
}

def call_dyn(x: any ShowDyn) -> i32 { x.show() }

def main() -> i32 {
    let a = DynA { v: 42 };
    call_dyn(a)
}
