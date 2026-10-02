
import std.collections
import std.option
struct State { var calls: i32; }
struct Item { var name: String; }
def make() -> Vec<Item> {
    let values = Vec<Item>.new(); values.push(Item { name: "a" }); values.push(Item { name: "b" });
    return filter_vec(values, (item: Item) -> { return true; });
}
def main() -> i32 {
    let state = State { calls: 0 };
    let prefix = "name=";
    let names = map_vec(make(), (item: Item) -> { return prefix + item.name; });
    if !join_strings(names, "\0").equals("name=a\0name=b") { return 1; }
    let values = Vec<i32>.new(); values.push(1); values.push(2); values.push(3);
    if !any_vec(values, (n: i32) -> { state.calls = state.calls + 1; return n == 2; }) { return 2; }
    if state.calls != 2 { return 3; }
    let absent: i32? = nil;
    let result = option_map(absent, (n: i32) -> { state.calls = 99; return n.to_string(); });
    if let value = result { return 4; }
    if state.calls != 2 { return 5; }
    return 0;
}
