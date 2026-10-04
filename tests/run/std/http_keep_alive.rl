import std.io
import std.http
import std.time
def handle(request: HttpRequest) async -> HttpResponse {
    if request.path().equals("/close") {
        let response = HttpResponse.text("bye");
        response.headers.set("Connection", "close");
        return response;
    }
    HttpResponse.text(f"{request.method} {request.path()} {request.body.len()}")
}
def main() async -> i32 {
    guard let server = HttpServer.bind("127.0.0.1", 0).ok_value() else { return 1; }
    server.idle_timeout = Duration.millis(300);
    let base = f"http://127.0.0.1:{server.port()}";
    // 5 requests on one connection, then a server-closed idle one, then Connection: close.
    let serving = spawn server.serve(handle, 3);
    let client = HttpClient.new();
    for index in 0..<5 {
        switch await client.get(f"{base}/item/{index}") { case .ok(let r): print(f"{r.body}; "); case .err(let e): print(e.message); }
    }
    println(f"idle {client.idle_connections()}");
    switch await client.post(base + "/upload", "x".repeat(1000)) { case .ok(let r): println(r.body); case .err(let e): println(e.message); }
    // The server drops the idle connection after 300 ms; the client retries on a new one.
    await sleep_for(Duration.millis(600));
    switch await client.get(base + "/after-idle") { case .ok(let r): println(r.body); case .err(let e): println(e.message); }
    switch await client.get(base + "/close") { case .ok(let r): println(f"{r.body} idle {client.idle_connections()}"); case .err(let e): println(e.message); }
    // keep_alive off: every request has its own connection.
    let single = HttpClient.new();
    single.keep_alive = false;
    switch await single.get(base + "/one") { case .ok(let r): println(f"{r.body} idle {single.idle_connections()}"); case .err(let e): println(e.message); }
    client.close_idle();
    switch await serving { case .ok(let n): println(f"server accepted {n} connections"); case .err(let e): println(e.message); }
    0
}
