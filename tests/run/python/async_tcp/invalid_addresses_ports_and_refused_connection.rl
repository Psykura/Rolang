
import std.async_io
import std.task
import std.result
def closed_port() -> i32 {
    switch AsyncListener.bind("127.0.0.1", 0, 8) {
        case .ok(let listener): return listener.port();
        case .err(let e): return -e;
    }
}
def main() async -> i32 {
    switch await AsyncStream.connect("localhost", 80) {
        case .ok(let s): return 1;
        case .err(let e): if e <= 0 { return 2; }
    }
    switch await AsyncStream.connect("127.0.0.1", 65536) {
        case .ok(let s): return 3;
        case .err(let e): if e <= 0 { return 4; }
    }
    switch AsyncListener.bind("bad", 0, 8) {
        case .ok(let s): return 5;
        case .err(let e): if e <= 0 { return 6; }
    }
    switch AsyncListener.bind("127.0.0.1", 0, 0) {
        case .ok(let s): return 7;
        case .err(let e): if e <= 0 { return 8; }
    }
    let port = closed_port();
    if port <= 0 { return 9; }
    switch await AsyncStream.connect("127.0.0.1", port) {
        case .ok(let s): return 10;
        case .err(let e): if e <= 0 { return 11; }
    }
    return 0;
}
