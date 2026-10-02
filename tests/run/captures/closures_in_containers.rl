struct Holder { var f: () -> i32; }
def main() -> i32 {
    let getters = Vec<() -> i32>.new();
    for i in 0..<3 { let value = i * 10; getters.push(() -> { value }); }
    let table: [String: (i32) -> i32] = [:];
    for k in 1...2 { let factor = k; table[f"x{k}"] = (n) -> { n * factor }; }
    let holders = Vec<Holder>.new();
    for i in 0..<2 { holders.push(Holder { f: () -> { i + 40 } }); }
    let maybe: [(() -> i32)?] = [() -> { 7 }, nil];
    if getters[0]() == 0 && getters[1]() == 10 && getters[2]() == 20 && (table["x2"] ?? (n) -> { 0 })(21) == 42
        && holders[1].f() == 41 && maybe[1] == nil { return 0; }
    1
}
