import std.io
import std.random
struct Item { let key: i32; let order: i32; }
def main() -> i32 {
    let rng = Random.seeded(1);
    // Stable for every size around the run length and the merge widths.
    for size in [0, 1, 2, 15, 16, 17, 31, 32, 33, 100, 1000, 5000] {
        let items = Vec<Item>.new();
        for i in 0..<size { items.push(Item { key: rng.int(0, 50) as i32, order: i }); }
        items.sort_by((a, b) -> { a.key < b.key });
        if items.len() != size { return 1; }
        for i in 1..<items.len() {
            let a = items[i - 1]; let b = items[i];
            if a.key > b.key || (a.key == b.key && a.order > b.order) { println(f"unstable at size {size}, index {i}"); return 2; }
        }
    }
    let words = ["pear", "apple", "fig", "banana"];
    let sorted = words.sorted_by((a, b) -> { a < b });
    println(f"{sorted[0]} {sorted[1]} {sorted[2]} {sorted[3]} {words[0]}");
    let numbers = [1, 3, 5, 7, 9, 11];
    println(f"{numbers.binary_search_by((x) -> { x - 7 }) ?? -1} {numbers.binary_search_by((x) -> { x - 8 }) ?? -1} {numbers.partition_point((x) -> { x < 6 })} {numbers.index_where((x) -> { x > 4 }) ?? -1}");
    numbers.reverse(); numbers.swap(0, 5);
    println(f"{numbers[0]} {numbers[5]} {numbers.reversed()[0]}");
    0
}
