
import std.collections
import std.option
import std.result
struct Item { var n: i32; }
def number(item: Item) -> i32 { return item.n; }
def even(n: i32) -> Bool { return n % 2 == 0; }
def add(a: i32, b: i32) -> i32 { return a + b; }
def text(n: i32) -> String { return n.to_string(); }
def positive(n: i32) -> String? { if n > 0 { return text(n); } return nil; }
def label(e: i32) -> String { return "error " + text(e); }
def good(n: i32) -> Result<String, String> { return Result.ok(value: text(n)); }
def main() -> i32 {
    let input = Vec<Item>.new();
    input.push(Item { n: 1 }); input.push(Item { n: 2 }); input.push(Item { n: 4 });
    let numbers = map_vec(input, number);
    let chosen = filter_vec(numbers, even);
    if fold_vec(chosen, 0, add) != 6 { return 1; }
    if (find_vec(numbers, even) ?? 0) != 2 { return 2; }
    if !any_vec(numbers, even) || all_vec(numbers, even) { return 3; }
    let empty = Vec<i32>.new();
    if any_vec(empty, even) || !all_vec(empty, even) { return 4; }
    if let missing = find_vec(empty, even) { return 5; }
    let names = map_vec(slice_vec(numbers, -1, 2), text);
    if !join_strings(names, ", ").equals("1, 2") { return 6; }
    if !join_strings(Vec<String>.new(), ",").is_empty() { return 7; }
    if slice_vec(numbers, 5, 1).len() != 0 { return 8; }
    if !(option_map(option_filter(4, even), text) ?? "").equals("4") { return 9; }
    if let missing = option_and_then(0, positive) { return 10; }
    let failed: Result<i32, i32> = Result.err(error: 7);
    switch map_err(failed, label) {
        case .ok(let n): return 11;
        case .err(let e): if !e.equals("error 7") { return 12; }
    }
    let success: Result<i32, String> = Result.ok(value: 42);
    switch and_then(success, good) {
        case .ok(let s): if !s.equals("42") { return 13; }
        case .err(let e): return 14;
    }
    return 0;
}
