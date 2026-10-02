
import std.async_io
import std.result
import std.task
def writer(stream: AsyncStream) async -> i32 {
    let data = "x".repeat(1048576);
    let result = await stream.write(data);
    stream.shutdown_write();
    switch result { case .ok(let n): return n; case .err(let e): return -e; }
}
def main() async -> i32 {
    if let pair = AsyncPipe.create() {
        let bad = await pair.first.read(-1);
        if !is_err(bad) { return 1; }
        let empty = await pair.first.read(0);
        switch empty { case .ok(let s): if s.len() != 0 { return 2; } case .err(let e): return 3; }
        let task = spawn writer(pair.second);
        await sleep(5);
        var count: i64 = 0;
        while true {
            let r = await pair.first.read(4096);
            switch r {
                case .ok(let s):
                    if s.len() == 0 { break; }
                    if s.char_at(0) != 120 { return 4; }
                    count = count + s.len();
                case .err(let e): return 5;
            }
        }
        if (await task) != 1048576 { return 6; }
        if count != 1048576 { return 7; }
        return 0;
    }
    return 8;
}
