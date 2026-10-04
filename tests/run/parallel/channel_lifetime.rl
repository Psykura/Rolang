import std.io
import std.task
extern "C" def rt_channel_live_count() -> i64;
def live() -> i64 { var count: i64 = 0; unsafe { count = rt_channel_live_count(); } count }

struct Link: Sendable { let name: String; let next: Channel<Link>; }
struct Note: Sendable { let text: String; let reply: Channel<String>; }

parallel def answer(notes: Channel<Note>) async -> i32 {
    var answered = 0;
    while let note = await notes.receive() { await note.reply.send(f"re: {note.text}"); answered += 1; }
    answered
}
parallel def keep(channel: Channel<i32>, count: i32) async -> Void {
    for i in 0..<count { await channel.send(i); }
}

def scenarios() async -> Void {
    // A channel queued inside itself.
    let own = Channel<Link>.new();
    await own.send(Link { name: "self", next: own });
    // Two channels queued inside each other.
    let a = Channel<Link>.new();
    let b = Channel<Link>.new();
    await a.send(Link { name: "to b", next: b });
    await b.send(Link { name: "to a", next: a });
    // A ring of three, one value received and dropped on the way.
    let x = Channel<Link>.new();
    let y = Channel<Link>.new();
    let z = Channel<Link>.new();
    await x.send(Link { name: "y", next: y });
    await y.send(Link { name: "z", next: z });
    await z.send(Link { name: "x", next: x });
    await z.send(Link { name: "x again", next: x });
    if let link = await z.receive() { println(f"took {link.name}"); }
    // A value holding a channel, dropped while queued in a channel nobody receives from.
    let outer = Channel<Note>.new();
    await outer.send(Note { text: "lost", reply: Channel<String>.new() });
    // Channels encoded for another thread and handed back.
    let notes = Channel<Note>.bounded(2);
    let worker = spawn answer(notes);
    for i in 0..<20 {
        let reply = Channel<String>.bounded(1);
        await notes.send(Note { text: f"{i}", reply: reply });
        if i == 19 { println((await reply.receive()) ?? "none"); } else { await reply.receive(); }
    }
    notes.close();
    println(f"answered {await worker}");
    // A channel still holding values a worker sent.
    let numbers = Channel<i32>.new();
    await keep(numbers, 50);
    println(f"queued {numbers.len()}");
}

def main() async -> i32 {
    await scenarios();
    println(f"after scenarios {live()}");
    // Values a live channel still holds keep the channels inside them alive.
    let holder = Channel<Link>.new();
    let inner = Channel<Link>.new();
    await holder.send(Link { name: "inner", next: inner });
    await inner.send(Link { name: "back", next: holder });
    println(f"held {live()}");
    if let link = await holder.receive() {
        println(f"{link.name} {link.next.len()}");
    }
    println(f"left {live()}");
    0
}
