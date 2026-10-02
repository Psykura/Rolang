
import std.iterator
struct State { var calls: i32; }
def make(state: State) -> Iter<String> {
    let values = Vec<i32>.new(); values.push(1); values.push(2); values.push(3); values.push(4);
    let mapped = iter_map(iter_vec(values), (n: i32) -> { state.calls = state.calls + 1; return n + 10; });
    let filtered = iter_filter(mapped, (n: i32) -> { return n % 2 == 0; });
    return iter_map(iter_take(filtered, 1), (n: i32) -> { return n.to_string(); });
}
def add(a: i32, b: i32) -> i32 { return a + b; }
def main() -> i32 {
    let state = State { calls: 0 };
    let source = make(state);
    if state.calls != 0 { return 1; }
    let result = iter_collect(source);
    if state.calls != 2 || result.len() != 1 || !result.get(0).equals("12") { return 2; }
    if let extra = source.__next__() { return 3; }
    if state.calls != 2 { return 4; }
    let values = Vec<i32>.new(); values.push(20); values.push(22);
    let names = Vec<String>.new(); names.push("a"); names.push("b"); names.push("c");
    var count = 0;
    for entry in iter_enumerate(iter_zip(iter_vec(values), iter_vec(names))) {
        if entry.index != (count as i64) { return 5; }
        if entry.value.first != values.get(count) { return 6; }
        if !entry.value.second.equals(names.get(count)) { return 7; }
        count = count + 1;
    }
    if count != 2 { return 8; }
    if iter_fold(iter_vec(values), 0, add) != 42 { return 9; }
    let untouched = make(state);
    if iter_collect(iter_take(untouched, 0)).len() != 0 || state.calls != 2 { return 10; }
    return 0;
}
