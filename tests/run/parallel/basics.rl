import std.io
import std.parallel
import std.task
import std.result

struct Point: Sendable { let x: f64; let y: f64; }
struct Batch: Sendable { let name: String; let points: Vec<Point>; let tags: Dict<String, i32>; let note: String?; }
enum Shape: Sendable { case circle(radius: f64); case rect(f64, f64); case empty; }
struct Summary: Sendable { let name: String; let count: i32; let sum: f64; let shapes: Vec<Shape>; let flags: Vec<Bool?>; }

// Runs on a worker thread; arguments and the result are copied across.
parallel def summarize(batch: Batch, scale: f64 = 2.0) async -> Summary {
    var sum = 0.0;
    for point in batch.points { sum += (point.x + point.y) * scale; }
    let shapes: Vec<Shape> = [.circle(radius: sum), .rect(1.0, 2.0), .empty];
    Summary { name: batch.name + (batch.note ?? ""), count: batch.points.len() as i32, sum, shapes, flags: [true, nil, false] }
}

parallel def collatz(start: i64) async -> i32 {
    var n = start; var steps = 0;
    while n != 1 { if n % 2 == 0 { n = n / 2; } else { n = 3 * n + 1; } steps += 1; }
    steps
}

parallel def labeled(of value: i32, times: i32) async -> Result<i32, String> {
    if times < 0 { return Result<i32, String>.err(error: "negative"); }
    Result<i32, String>.ok(value: value * times)
}

parallel def nothing(message: String) async -> Void { }

def describe(shape: Shape) -> String {
    switch shape { case .circle(let r): f"circle {r}"; case .rect(let w, let h): f"rect {w}x{h}"; case .empty: "empty"; }
}

def main() async -> i32 {
    let batch = Batch { name: "b", points: [Point { x: 1.0, y: 2.0 }, Point { x: 3.0, y: 4.0 }], tags: ["a": 1], note: "!" };
    let summary = await summarize(batch);
    println(f"{summary.name} {summary.count} {summary.sum} {summary.flags.len()} {summary.flags[1] == nil}");
    for shape in summary.shapes { println(describe(shape)); }
    println(f"{(await summarize(batch, scale: 1.0)).sum}");
    await nothing("x");
    // Spawned calls run in parallel; awaiting collects the results in order.
    let tasks = Vec<Task<i32>>.new();
    for start in 1..<30 { tasks.push(spawn collatz(start as i64)); }
    var steps = "";
    for task in tasks { steps = steps + f"{await task} "; }
    println(steps);
    println(f"{(await labeled(of: 6, times: 7)).ok_value() ?? -1} {(await labeled(of: 1, times: -1)).err_value() ?? "-"}");
    println(f"{parallel_workers() > 0} {on_worker_thread()}");
    0
}
