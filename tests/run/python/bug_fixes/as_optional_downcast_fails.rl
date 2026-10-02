
import "io.rl"

protocol Animal {
    def sound() -> i32;
}

struct Dog {
    var id: i32;
    def sound() -> i32 { return 1; }
}

struct Cat {
    var id: i32;
    def sound() -> i32 { return 2; }
}

def main() -> i32 {
    let d = Dog { id: 7 };
    let a: any Animal = d;
    let maybe: Cat? = a as? Cat;
    switch maybe {
        case .Some(let c): return c.id;
        case nil: return 0;
    }
}
