import std.io
import std.task
import std.dict

// Producers on workers feed a bounded channel the main task drains.
parallel def produce(start: i64, count: i32, out: Channel<i64>) async -> i64 {
    var sum: i64 = 0;
    for i in 0..<count { let value = start + (i as i64); sum += value; await out.send(value); }
    sum
}

// A pool of workers sharing one job channel until it is closed.
struct Job: Sendable { let id: i32; let words: Vec<String>; }
struct Report: Sendable { let id: i32; let letters: i64; }
parallel def worker(jobs: Channel<Job>, reports: Channel<Report>) async -> i32 {
    var handled = 0;
    while let job = await jobs.receive() {
        var letters: i64 = 0;
        for word in job.words { letters += word.len() as i64; }
        await reports.send(Report { id: job.id, letters: letters });
        handled += 1;
    }
    handled
}

// A channel travels inside a value and through another channel.
struct Reply: Sendable { let question: String; let answer: Channel<String>; }
parallel def answer_one(requests: Channel<Reply>) async -> Void {
    if let request = await requests.receive() {
        await request.answer.send(f"answer to {request.question}");
    }
}

def receive_one(channel: Channel<i32>) async -> i32? { await channel.receive() }

def main() async -> i32 {
    let numbers = Channel<i64>.bounded(4);
    let first = spawn produce(0, 1000, numbers);
    let second = spawn produce(1000, 1000, numbers);
    var total: i64 = 0;
    for i in 0..<2000 { total += (await numbers.receive()) ?? 0; }
    println(f"{total == (await first) + (await second)} {total} left {numbers.len()}");

    let jobs = Channel<Job>.bounded(8);
    let reports = Channel<Report>.new();
    let pool = Vec<Task<i32>>.new();
    for i in 0..<4 { pool.push(spawn worker(jobs, reports)); }
    for id in 0..<200 {
        let words = Vec<String>.new();
        for w in 0..<(id % 5) { words.push("word"); }
        await jobs.send(Job { id: id, words: words });
    }
    jobs.close();
    println(f"send after close {await jobs.send(Job { id: -1, words: Vec<String>.new() })} closed {jobs.is_closed()}");
    var handled = 0;
    for task in pool { handled += await task; }
    let letters = Dict<i32, i64>.new();
    while let report = reports.try_receive() { letters[report.id] = report.letters; }
    println(f"handled {handled} reports {letters.len()} id 7 {letters[7] ?? -1} id 9 {letters[9] ?? -1}");

    let requests = Channel<Reply>.new();
    let answering = spawn answer_one(requests);
    let answer = Channel<String>.bounded(1);
    await requests.send(Reply { question: "life", answer: answer });
    println((await answer.receive()) ?? "none");
    await answering;

    // On one thread, without workers.
    let local = Channel<i32>.bounded(1);
    println(f"try {local.try_receive() ?? -1} {local.try_send(1)} {local.try_send(2)} {local.len()}");
    println(f"got {(await local.receive()) ?? -1}");
    // A cancelled receiver's wake passes to the next one.
    let cancelled = spawn receive_one(local);
    let waiting = spawn receive_one(local);
    await yield_now();
    cancelled.cancel();
    await local.send(5);
    println(f"other receiver {(await waiting) ?? -1}");
    local.close();
    println(f"drained {(await local.receive()) ?? -1}");
    0
}
