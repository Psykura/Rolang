import std.io
import std.http
import std.async_io
import std.time
import std.task
def handle(request: HttpRequest) async -> HttpResponse { HttpResponse.text("hi") }
def main() async -> i32 {
    guard let server = HttpServer.bind("127.0.0.1", 0).ok_value() else { return 1; }
    server.idle_timeout = Duration.millis(200);
    let serving = spawn server.serve(handle, 1);
    // A client that connects and never sends anything is dropped.
    guard let silent = (await AsyncStream.connect("127.0.0.1", server.port())).ok_value() else { return 2; }
    let start = Instant.now();
    let data = (await silent.read(100)).ok_value() ?? "?";
    println(f"closed {data.len() == 0} {start.elapsed() < Duration.seconds(2)}");
    await serving;
    0
}
