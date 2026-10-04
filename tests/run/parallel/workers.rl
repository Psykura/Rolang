import std.io
import std.parallel
import std.task
import std.time
import std.regex
import std.crypto
import std.encoding
import std.json
import std.async_fs

struct Node { var next: Node?; let label: String; }

parallel def leaf(n: i64) async -> i64 { n * 2 }

// On a worker: local tasks, sleeping, a nested parallel call, file I/O.
parallel def busy(id: i32) async -> String {
    let local = spawn leaf_local(id);
    await sleep_for(Duration.millis(5));
    let nested = await leaf(id as i64);
    let written = await write_file(f"/tmp/rolang-par-{id}.txt", f"job {id}");
    let back = (await read_file(f"/tmp/rolang-par-{id}.txt")).ok_value() ?? "?";
    await remove(f"/tmp/rolang-par-{id}.txt");
    f"{id}:{await local}:{nested}:{back}:{on_worker_thread()}"
}
def leaf_local(id: i32) async -> i32 { await yield_now(); id + 100 }

// Cyclic garbage, collected by the worker's own cycle collector.
parallel def churn(rounds: i32) async -> i32 {
    var made = 0;
    for index in 0..<rounds {
        let a = Node { next: nil, label: "a" };
        let b = Node { next: a, label: "b" };
        a.next = b;
        made += 1;
    }
    made
}

// Standard library code running on several threads at once.
parallel def mixed(text: String) async -> String {
    let words = Regex.new(r"\w+").ok_value()?.find_all(text).len() ?? -1;
    let digest = hex_encode(hash(HashAlgorithm.sha256, text).ok_value() ?? "").substring(0, 8);
    let json = Json.parse(f"{{\"n\": {words}}}").ok_value()?.to_string() ?? "?";
    f"{words} {digest} {json}"
}

parallel def tiny(n: i32) async -> i32 { n + 1 }

def main() async -> i32 {
    let tasks = Vec<Task<String>>.new();
    for id in 0..<4 { tasks.push(spawn busy(id)); }
    for task in tasks { println(await task); }
    let churns = Vec<Task<i32>>.new();
    for index in 0..<4 { churns.push(spawn churn(200000)); }
    var total = 0;
    for task in churns { total += await task; }
    println(f"churned {total}");
    let texts = Vec<Task<String>>.new();
    for index in 0..<16 { texts.push(spawn mixed(f"hello parallel world {index % 2}")); }
    var distinct = Dict<String, Bool>.new();
    for task in texts { distinct[await task] = true; }
    println(f"mixed results {distinct.len()}");
    let many = Vec<Task<i32>>.new();
    for index in 0..<10000 { many.push(spawn tiny(index)); }
    var sum: i64 = 0;
    for task in many { sum += (await task) as i64; }
    println(f"10000 jobs sum {sum}");
    0
}
