struct Box { var items: [i64]; var names: [String: [i32]]; }
def opt() -> [i32]? { [] }
def main() -> i32 {
    let wide: [i64] = [1, 2, 39];
    let nested: [[i32]] = [[], [42]];
    let b = Box { items: [], names: ["a": []] };
    b.items.push(5);
    var total: i64 = 0;
    for x in wide { total += x; }
    let maybe: [String: i32]? = [:];
    if total == 42 && nested[1][0] == 42 && nested[0].len() == 0 && b.items.len() == 1 && (opt() ?? [1]).len() == 0 && (maybe?.len() ?? -1) == 0 { return 0; }
    1
}
