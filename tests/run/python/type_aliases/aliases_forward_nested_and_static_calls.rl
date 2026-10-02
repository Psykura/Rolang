
import std.vec
typealias NodeId = Index;
typealias Index = i32;
typealias Nodes = Vec<NodeId>;
typealias Maybe = NodeId?;
typealias Callback = (NodeId) -> NodeId;
typealias Record = Item;
struct Item { var number: NodeId; }
def next(n: NodeId) -> Index { return n + 1; }
def main() -> i32 {
    let nodes: Nodes = Nodes.new();
    let callback: Callback = next;
    nodes.push(callback(4));
    let item = Record { number: nodes.get(0) };
    let optional: Maybe = item.number;
    if let value = optional { return value - 5; }
    return 9;
}
