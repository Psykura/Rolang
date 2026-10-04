import std.io
import std.http
import std.json
import std.task
import std.async_io

def handle(request: HttpRequest) async -> HttpResponse {
    let path = request.path();
    if path.equals("/hello") { return HttpResponse.text(f"hello {request.query()["name"] ?? "world"}"); }
    if path.equals("/echo") { return HttpResponse.json(request.json().ok_value() ?? Json.null(), 201); }
    if path.equals("/old") { return HttpResponse.redirect("/hello?name=moved"); }
    HttpResponse.text("not found", 404)
}

// Answers one connection with a chunked body.
def chunked_server(listener: AsyncListener) async -> Void {
    guard let stream = (await listener.accept()).ok_value() else { return; }
    let request = await stream.read(65536);
    await stream.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n7;ext=1\r\n, world\r\n0\r\nTrailer: x\r\n\r\n");
    stream.shutdown_write();
}

def main() async -> i32 {
    guard let server = HttpServer.bind("127.0.0.1", 0).ok_value() else { return 1; }
    let base = f"http://127.0.0.1:{server.port()}";
    // Five connections: four requests (a redirect's second request reuses its
    // client's connection) and one keep-alive connection.
    let serving = spawn server.serve(handle, 5);
    switch await http_get(base + "/hello?name=ro%20lang") {
        case .ok(let r): println(f"{r.status} {r.reason} {r.headers.get("content-type") ?? "?"} {r.body}");
        case .err(let e): println(e.to_string());
    }
    let payload = Json.empty_object(); payload.set("n", Json.int(7));
    switch await HttpClient.new().post_json(base + "/echo", payload) {
        case .ok(let r): println(f"{r.status} {r.body} {r.json_body().ok_value()?["n"]?.as_int() ?? 0}");
        case .err(let e): println(e.to_string());
    }
    switch await http_get(base + "/old") { case .ok(let r): println(f"{r.status} {r.body}"); case .err(let e): println(e.to_string()); }
    switch await http_get(base + "/missing") { case .ok(let r): println(f"{r.status} {r.ok()}"); case .err(let e): println(e.to_string()); }
    // Two requests on one keep-alive connection.
    guard let raw = (await AsyncStream.connect("127.0.0.1", server.port())).ok_value() else { return 2; }
    await raw.write("GET /hello HTTP/1.1\r\nHost: a\r\n\r\nGET /hello?name=again HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n");
    var replies = "";
    while true { guard let data = (await raw.read(65536)).ok_value() else { break; } if data.len() == 0 { break; } replies += data; }
    println(f"keep-alive {replies.split("HTTP/1.1 200").len() - 1} {replies.contains("hello again")}");
    switch await serving { case .ok(let n): println(f"served {n} connections"); case .err(let e): println(e.to_string()); }

    guard let listener = AsyncListener.bind("127.0.0.1", 0, 4).ok_value() else { return 3; }
    let chunked = spawn chunked_server(listener);
    switch await http_get(f"http://127.0.0.1:{listener.port()}/") { case .ok(let r): println(f"chunked {r.body}"); case .err(let e): println(e.to_string()); }
    await chunked;

    switch await http_get("http://127.0.0.1:1/") { case .ok(let r): println("?"); case .err(let e): println(e.to_string()); }
    let url = Url.parse("http://Example.com:8080/a/b?x=1#frag");
    println(f"{url?.host ?? "?"} {url?.port ?? 0} {url?.target() ?? "?"} {url?.join("../c?y=2")?.to_string() ?? "?"} {url?.join("/d")?.to_string() ?? "?"}");
    println(f"{percent_encode("a b/ü")} {percent_decode("a%20b%2F%C3%BC") ?? "?"} {parse_query("q=two+words&n=1")["q"] ?? "?"} {Url.parse("ftp://x") == nil}");
    0
}
