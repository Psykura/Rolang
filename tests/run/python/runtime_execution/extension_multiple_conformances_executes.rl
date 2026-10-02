// expect-exit: 42

protocol MultiShow { def show() -> i32; }
protocol MultiTag { def tag() -> i32; }

struct MultiA { var v: i32 }

extension MultiA: MultiShow, MultiTag {
    def show() -> i32 { self.v }
    def tag() -> i32 { self.v + 1 }
}

def call_show(x: any MultiShow) -> i32 { x.show() }
def call_tag(x: any MultiTag) -> i32 { x.tag() }

def main() -> i32 {
    let a = MultiA { v: 41 };
    call_show(a) + call_tag(a) - 41
}
