// expect-exit: 25

import "io.rl"

protocol Shape {
    def area() -> i32;
}

struct Circle {
    var r: i32;
    def area() -> i32 { return self.r * self.r; }
}

def main() -> i32 {
    let c = Circle { r: 5 };
    let s: any Shape = c;
    let maybe: Circle? = s as? Circle;
    switch maybe {
        case .Some(let got): return got.area();
        case nil: return -1;
    }
}
