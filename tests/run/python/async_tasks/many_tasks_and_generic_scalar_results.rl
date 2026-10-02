
import std.task
import std.vec
def identity<T>(value: T) async -> T { await yield_now(); return value; }
def nothing() async -> Void { await sleep(-1); }
struct Worker {
    def answer(n: i32) async -> i32 { return n; }
}
def main() async -> i32 {
    let tasks = Vec<Task<i32>>.new();
    var i = 0;
    while i < 600 { tasks.push(spawn identity(i)); i = i + 1; }
    i = 0;
    while i < 600 {
        let task = tasks.get(i);
        if (await task) != i { return 1; }
        i = i + 1;
    }
    let wide = spawn identity(9223372036854775807);
    if (await wide) != 9223372036854775807 { return 2; }
    let float = spawn identity(1.25);
    if (await float) != 1.25 { return 3; }
    let flag = spawn identity(true);
    if !(await flag) { return 4; }
    let done = spawn nothing();
    await done;
    await done;
    let worker = Worker {};
    let method = spawn worker.answer(42);
    if (await method) != 42 { return 5; }
    return 0;
}
