struct Node { var next: Node?; var v: i32; }
def main() -> i32 {
    let a: i32? = 4; let b: i32? = nil; let n = Node { next: nil, v: 1 };
    if a != nil && b == nil && nil != a && nil == b && n.next == nil && a.is_some() && b.is_none() { return 0; }
    1
}
