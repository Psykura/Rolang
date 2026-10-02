struct Counter { var hits: i32 = 0; var tags: [String] = []; var limit: i64 = 10; }
struct Wrapper<T> { var item: T; var count: i32 = 1; }
def main() -> i32 {
    let a = Counter {}; let b = Counter {};
    a.tags.push("x");
    let c = Counter { hits: 5 };
    let w = Wrapper<String> { item: "s" };
    if a.tags.len() == 1 && b.tags.len() == 0 && c.hits == 5 && a.limit == 10 && w.count == 1 { return 0; }
    1
}
