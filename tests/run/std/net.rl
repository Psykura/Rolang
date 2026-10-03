import std.io
import std.async_io
import std.task
def main() async -> i32 {
    switch resolve("localhost") { case .ok(let list): println(f"localhost {list.contains("127.0.0.1") || list.contains("::1")}"); case .err(let e): println("resolve failed: " + e); }
    switch resolve("no-such-host.invalid") { case .ok(let list): println("resolved?"); case .err(let e): println("unknown host fails"); }
    guard let server = UdpSocket.bind("127.0.0.1", 0).ok_value() else { return 1; }
    guard let client = UdpSocket.bind("127.0.0.1", 0).ok_value() else { return 2; }
    let receiving = spawn server.receive();
    switch await client.send_to("ping\u{0}pong", "127.0.0.1", server.port()) { case .ok(let n): println(f"sent {n}"); case .err(let code): println(os_error_message(code)); }
    switch await receiving { case .ok(let d): println(f"got {d.data.len()} bytes from {d.address} {d.port == client.port()}"); case .err(let code): println(os_error_message(code)); }
    switch await AsyncStream.connect("localhost", 1) { case .ok(let s): println("connected?"); case .err(let code): println(os_error_message(code)); }
    0
}
