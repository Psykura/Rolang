import std.io
import std.http
import std.async_io
def handle(request: HttpRequest) async -> HttpResponse {
    if request.path().equals("/big") { return HttpResponse.text("compressible line\n".repeat(500)); }
    HttpResponse.text("small")
}
def main() async -> i32 {
    guard let server = HttpServer.bind("127.0.0.1", 0).ok_value() else { return 1; }
    server.gzip = true;
    let base = f"http://127.0.0.1:{server.port()}";
    let serving = spawn server.serve(handle, 3);
    switch await http_get(base + "/big") { case .ok(let r): println(f"{r.status} {r.body.len()} {r.headers.get("Content-Encoding") ?? "-"}"); case .err(let e): println(e.to_string()); }
    // A raw request shows what travels on the wire.
    guard let raw = (await AsyncStream.connect("127.0.0.1", server.port())).ok_value() else { return 2; }
    await raw.write("GET /big HTTP/1.1\r\nHost: x\r\nAccept-Encoding: gzip\r\nConnection: close\r\n\r\n");
    let wire = (await raw.read_to_end()).ok_value() ?? "";
    println(f"{wire.contains("Content-Encoding: gzip")} {wire.len() < 2000}");
    switch await http_get(base + "/small") { case .ok(let r): println(f"{r.body} {r.headers.get("Content-Encoding") ?? "-"}"); case .err(let e): println(e.to_string()); }
    await serving;
    0
}
