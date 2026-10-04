import std.io
import std.http
import std.result
import std.async_io
import std.encoding
def echo(request: HttpRequest, socket: WebSocket) async -> Void {
    while true {
        switch await socket.receive() {
            case .ok(let message):
                guard let received = message else { return; }
                switch received {
                    case .text(let text): await socket.send_text(f"echo {request.path()}: {text}");
                    case .binary(let data): await socket.send_binary(data + data);
                }
            case .err(let error): println(f"server: {error.message}"); return;
        }
    }
}
def plain(request: HttpRequest) async -> HttpResponse { HttpResponse.text("plain http") }
def main() async -> i32 {
    guard let server = HttpServer.bind("127.0.0.1", 0).ok_value() else { return 1; }
    server.websocket = echo;
    let serving = spawn server.serve(plain, 4);
    switch await WebSocket.connect(f"ws://127.0.0.1:{server.port()}/chat") {
        case .ok(let ws):
            await ws.send_text("hello");
            println(describe(await ws.receive()));
            await ws.send_binary("\0\u{1}");
            println(describe(await ws.receive()));
            let big = "x".repeat(200000);
            await ws.send_text(big);
            println(f"{describe(await ws.receive()).len()}");
            await ws.ping("p");
            await ws.send_text("after ping");
            println(describe(await ws.receive()));
            await ws.close(1000, "bye");
            println(f"closed {ws.close_code ?? -1}");
        case .err(let error): println(error.message);
    }
    switch await http_get(f"http://127.0.0.1:{server.port()}/") { case .ok(let r): println(r.body); case .err(let e): println(e.message); }
    // An upgrade without a key is an ordinary request.
    guard let raw = (await AsyncStream.connect("127.0.0.1", server.port())).ok_value() else { return 2; }
    await raw.write("GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nConnection: close\r\n\r\n");
    println(((await raw.read_to_end()).ok_value() ?? "").split("\r\n")[0]);
    // A client frame without a mask is a protocol error.
    guard let bad = (await AsyncStream.connect("127.0.0.1", server.port())).ok_value() else { return 3; }
    await bad.write("GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n");
    let handshake = (await bad.read(4096)).ok_value() ?? "";
    println(f"{handshake.contains("101 Switching Protocols")} {handshake.contains("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")}");
    await bad.write((hex_decode("8102") ?? "") + "hi");
    // The server answers with a close frame (opcode 8, code 1002).
    let closing = (await bad.read(4096)).ok_value() ?? "";
    bad.shutdown_write();
    await serving;
    // After the server's own report, so the output order does not depend on scheduling.
    println(f"{hex_encode(closing.substring(0, 4))}");
    0
}
def describe(result: Result<WebSocketMessage?, HttpError>) -> String {
    switch result {
        case .ok(let message):
            guard let m = message else { return "closed"; }
            switch m { case .text(let t): return f"text {t}"; case .binary(let b): return f"binary {b.len()}"; }
        case .err(let e): return f"error {e.message}";
    }
}
