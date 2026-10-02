// expect-exit: 134

import std.task
def work() async -> i32 { return 1; }
def main() async -> i32 {
    let task = spawn work();
    task.cancel();
    return await task;
}
