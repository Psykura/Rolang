import std.task

def work(n: i32) async -> i32 {
    await yield_now();
    n * 2
}

def main() async -> i32 {
    let task = spawn work(21);
    let first = await task;
    let second = await task;
    if first == 42 && second == 42 && task.done() { return 0; }
    1
}
