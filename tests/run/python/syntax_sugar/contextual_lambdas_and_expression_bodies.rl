
import std.collections
struct Node { var name: String; var public: Bool; }
def apply<T, U>(f: (T) -> U, value: T) -> U { return f(value); }
def main() -> i32 {
    let nodes = Vec<Node>.new(); nodes.push(Node { name: "alpha", public: true });
    let names = map_vec(nodes, (node) -> { node.name });
    if !join_strings(names, ",").equals("alpha") { return 1; }
    if apply((x) -> { x + 1 }, 41) != 42 { return 2; }
    let f: (i32) -> i32 = (x) -> { x * 2 };
    if f(21) != 42 { return 3; }
    let lift: (i32) -> i32? = (x) -> { x };
    if (lift(42) ?? 0) != 42 { return 4; }
    let optional: (i32?) -> String? = (x) -> { let value = x?; f"{value}" };
    if !(optional(42) ?? "").equals("42") { return 5; }
    return 0;
}
