def or_default<T>(values: [T], fallback: T) -> T { if values.len() > 0 { return values[0]; } fallback }
def main() -> i32 {
    let groups = Dict<String, [i32]>.new();
    groups.set("a", []);
    let nested = Vec<[String: i32]>.new(); nested.push([:]);
    if (groups["a"] ?? [1]).len() != 0 || nested[0].len() != 0 || or_default([], 42) != 42 { return 1; }
    0
}
