struct Node { var next: Node?; var v: i32; }
def main() -> i32 {
    var total: i64 = 0;
    for i in 0..<200000 {
        var node = Node { next: nil, v: i };
        var f: () -> i32 = () -> { 0 };
        f = () -> { node.v + (if node.v < 0 { f() } else { 0 }) };
        let swap = () -> { node = Node { next: node, v: 1 }; };
        swap();
        total += f() as i64;
    }
    if total == 200000 { return 0; }
    1
}
