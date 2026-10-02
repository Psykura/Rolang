// expect-exit: 42

protocol Measurable {
    def size() -> i32;
}

struct Box {
    var w: i32;
    def size() -> i32 { return self.w; }
}

def main() -> i32 {
    let b = Box { w: 42 };
    let m: any Measurable = b;
    let got: Box = m as! Box;
    return got.w;
}
