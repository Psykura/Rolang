import std.task
struct Log { var text: String; }
def double(x: i32) async -> i32 { await yield_now(); x * 2 }
def note(log: Log, item: String) async -> Void { await yield_now(); log.text = log.text + item; }
def apply(f: (i32) async -> i32, value: i32) async -> i32 { await f(value) }
def make_adder(base: i32) -> (i32) async -> i32 { (n: i32) async -> i32 { await yield_now(); base + n } }
def main() async -> i32 {
    let f = double;
    if (await f(10)) != 20 || (await apply(double, 21)) != 42 { return 1; }
    let add = make_adder(40);
    if (await add(2)) != 42 || (await apply(add, 1)) != 41 { return 2; }
    var calls = 0;
    let counted: (i32) async -> i32 = (x) async -> { calls += 1; await yield_now(); x + calls };
    if (await counted(10)) != 11 || (await counted(10)) != 12 || calls != 2 { return 3; }
    let log = Log { text: "" };
    let writer = note;
    await writer(log, "a");
    let task = spawn writer(log, "b");
    let pending = spawn f(5);
    await task;
    if (await pending) != 10 || log.text != "ab" { return 4; }
    let tasks = Vec<(i32) async -> i32>.new(); tasks.push(double); tasks.push(add);
    var total = 0; for g in tasks { total += await g(1); }
    if total != 43 { return 5; }
    0
}
