import std.io
import std.async_io
import std.time
import std.task
def main() async -> i32 {
    let names = ["localhost", "127.0.0.1", "::1", "no-such-host.invalid"];
    for name in names {
        switch await resolve(name) { case .ok(let list): println(f"{name}: {list.len() > 0}"); case .err(let e): println(f"{name}: error"); }
    }
    // A cancelled lookup releases its job safely when the thread finishes.
    let pending = spawn resolve("example.invalid");
    pending.cancel();
    await sleep_for(Duration.millis(200));
    println("done");
    0
}
