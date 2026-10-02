import std.set
def counts<K>(keys: [K]) -> Dict<K, i32> {
    let d = Dict<K, i32>.new();
    for k in keys { d[k] = (d[k] ?? 0) + 1; }
    d
}
def main() -> i32 {
    let words = Dict<String, i32>.new();
    let a = "ab"; let b = "a" + "b";
    words[a] = 1; words[b] = 41;
    let ids = Dict<i64, String>.new(); ids[7] = "seven";
    let s = Set<String>.new(); s.add("x"); s.add("x" + ""); s.add("y");
    let n = Set<i32>.new(); n.add(1); n.add(1);
    let c = counts(["k", "k" + "", "z"]);
    if words.len() == 1 && (words["ab"] ?? 0) == 41 && (ids[7] ?? "").equals("seven") && s.len() == 2 && n.len() == 1
        && (c["k"] ?? 0) == 2 && c.len() == 2 { return 0; }
    1
}
