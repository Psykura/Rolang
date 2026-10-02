struct Node { var value: i32; var next: Node?; var items: [String: i32];
    def add(n: i32, scale: i32 = 1) -> i32 { self.value + n * scale }
    def label(prefix p: String) -> String { p + "!" }
    def find(key: String) -> i32? { self.items[key] } }
def main() -> i32 {
    let tail = Node { value: 2, next: nil, items: ["k": 7] };
    let head: Node? = Node { value: 40, next: tail, items: [:] };
    let missing: Node? = nil;
    if (head?.add(2) ?? 0) != 42 { return 1; }
    if (head?.add(1, scale: 2) ?? 0) != 42 { return 2; }
    if !(head?.label(prefix: "a") ?? "").equals("a!") { return 3; }
    if let unexpected = missing?.add(1) { return 4; }
    if (head?.next?.items["k"] ?? 0) != 7 { return 5; }
    if (head?.next?.find("k") ?? 0) != 7 { return 6; }
    if let unexpected = head?.find("absent") { return 7; }
    if (missing?.items["k"] ?? 3) != 3 { return 8; }
    if (head?.next?.value ?? 0) + (head?.value ?? 0) != 42 { return 9; }
    let next: Node? = head?.next;
    if let unexpected = head?.next?.next?.value { return 10; }
    if (next?.value ?? 0) != 2 { return 11; }
    0
}
