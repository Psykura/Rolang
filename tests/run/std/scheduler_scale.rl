import std.io
import std.task
// Many tasks waiting, yielding and being cancelled at once; each scheduler
// step costs time in its own work, not in the number of tasks alive.
def ping(n: i32) async -> i32 { await yield_now(); await yield_now(); n }
def chain(depth: i32) async -> i32 {
    if depth == 0 { return 0; }
    1 + await chain(depth - 1)
}
def forever() async -> Void { await sleep(600000); }
def main() async -> i32 {
    let tasks = Vec<Task<i32>>.new();
    for index in 0..<20000 { tasks.push(spawn ping(index)); }
    var total: i64 = 0;
    for task in tasks { total += (await task) as i64; }
    println(f"{total}");
    println(f"{await chain(2000)}");
    // Cancelled sleepers do not keep the program alive.
    let sleepers = Vec<Task<Void>>.new();
    for index in 0..<1000 { sleepers.push(spawn forever()); }
    var cancelled = 0;
    for sleeper in sleepers { if sleeper.cancel() { cancelled += 1; } }
    println(f"{cancelled}");
    0
}
