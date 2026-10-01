import std.async_io
import std.task
import std.result
import std.io
def client(port: i32) async -> i32 {
    switch await AsyncStream.connect("127.0.0.1", port) {
        case .err(let e): return e;
        case .ok(let stream):
            switch await stream.write("hello") {
                case .err(let e): return e;
                case .ok(let n): if n != 5 { return 1; }
            }
            stream.shutdown_write();
            switch await stream.read(10) {
                case .err(let e): return e;
                case .ok(let text): println(text);
            }
    }
    return 0;
}
def main() async -> i32 {
    switch AsyncListener.bind("127.0.0.1", 0, 16) {
        case .err(let e): return e;
        case .ok(let listener):
            if listener.port() <= 0 { return 2; }
            let pending = spawn listener.accept();
            await sleep(2);
            if pending.done() { return 3; }
            pending.cancel();
            if await pending.wait() { return 4; }
            let worker = spawn client(listener.port());
            switch await listener.accept() {
                case .err(let e): return e;
                case .ok(let stream):
                    var text = "";
                    while true {
                        switch await stream.read(2) {
                            case .err(let e): return e;
                            case .ok(let chunk):
                                if chunk.len() == 0 { break; }
                                text = text + chunk;
                        }
                    }
                    println(text);
                    switch await stream.write("ok") {
                        case .err(let e): return e;
                        case .ok(let n): if n != 2 { return 5; }
                    }
            }
            return await worker;
    }
}
