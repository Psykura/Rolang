
import "io.rl"

struct Node {
    var n: i32;
    var partner: Node?;

    def __release__() -> Void {
        if let p = self.partner {
            println("saw partner");
        } else {
            println("no partner");
        }
    }
}

def main() -> i32 {
    let a = Node { n: 1, partner: nil };
    let b = Node { n: 2, partner: a };
    return 0;
}
