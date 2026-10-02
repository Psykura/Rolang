
import std.async_io
import std.result
import std.task
import std.io
def writer(stream: AsyncStream) async -> i32 {
    await sleep(5);
    let result = await stream.write("hello");
    switch result { case .ok(let n): if n != 5 { return 1; } case .err(let e): return e; }
    return stream.shutdown_write();
}
def main() async -> i32 {
    if let pair = AsyncPipe.create() {
    let task = spawn writer(pair.second);
    var text = "";
    while true {
        let result = await pair.first.read(2);
        switch result {
            case .ok(let chunk):
                if chunk.len() == 0 { break; }
                text = text + chunk;
            case .err(let e): return e;
        }
    }
    println(text);
    return await task;
    }
    return 99;
}
