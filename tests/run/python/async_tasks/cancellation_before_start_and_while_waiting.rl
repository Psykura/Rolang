
import std.task
struct State { var value: i32; }
def child(state: State) async -> i32 {
    state.value = state.value + 1;
    await sleep(60000);
    state.value = 99;
    return 10;
}
def parent(state: State) async -> i32 { return await child(state); }
def main() async -> i32 {
    let state = State { value: 0 };
    let first = spawn child(state);
    if !first.cancel() { return 1; }
    if first.cancel() { return 2; }
    if await first.wait() { return 3; }
    if state.value != 0 { return 4; }
    let second = spawn parent(state);
    await sleep(5);
    if state.value != 1 { return 5; }
    if !second.cancel() { return 6; }
    if await second.wait() { return 7; }
    if !second.cancelled() { return 8; }
    return 0;
}
