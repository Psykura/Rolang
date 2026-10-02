
import std.task
import std.io
struct State { var value: i32; }
def worker(state: State, n: i32) async -> String {
    var i = 0;
    while i < 4 {
        state.value = state.value + 1;
        await yield_now();
        i = i + 1;
    }
    return "result" + n.to_string();
}
def main() async -> i32 {
    let state = State { value: 0 };
    let a = spawn worker(state, 1);
    let alias = a;
    let b = spawn worker(state, 2);
    println(await a);
    println(await alias);
    println(await b);
    if state.value != 8 { return 1; }
    if !a.done() { return 2; }
    if a.cancel() { return 3; }
    if !(await a.wait()) { return 4; }
    return 0;
}
