import std.task
def work() async -> i32 {
    var n = 0;
    let add = () -> { n += 21; };
    add();
    await yield_now();
    add();
    n
}
def main() async -> i32 { if (await work()) == 42 { return 0; } 1 }
