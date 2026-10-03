// TLS between local tasks. ca.pem is a test CA that issued cert.pem for
// localhost and 127.0.0.1; key.pem is that certificate's key.
import std.io
import std.tls
import std.http
import std.async_io

// Echoes everything a client sends, upper-cased, until the client closes.
// The result counts the clients that rejected the certificate.
def echo_server(listener: AsyncListener, config: TlsConfig, connections: i32) async -> i32 {
    var rejected = 0;
    for index in 0..<connections {
        guard let socket = (await listener.accept()).ok_value() else { return rejected; }
        switch await TlsStream.server(socket, config) {
            case .ok(let tls):
                while true {
                    guard let data = (await tls.read()).ok_value() else { break; }
                    if data.len() == 0 { break; }
                    await tls.write(data.uppercased());
                }
                await tls.close();
            case .err(let error): rejected += 1;
        }
    }
    rejected
}

// Reads until `count` bytes arrived or the stream ends.
def read_all(tls: TlsStream, count: i32) async -> String {
    var received = "";
    while (received.len() as i32) < count {
        guard let data = (await tls.read()).ok_value() else { break; }
        if data.len() == 0 { break; }
        received = received + data;
    }
    received
}

def handle(request: HttpRequest) async -> HttpResponse {
    if request.path().equals("/hello") { return HttpResponse.text("hello over https"); }
    if request.path().equals("/size") { return HttpResponse.text(f"{request.body.len()} bytes"); }
    HttpResponse.text("not found", 404)
}

def main() async -> i32 {
    guard let server_config = TlsConfig.server("cert.pem", "key.pem", ["h2", "http/1.1"]).ok_value() else { println("no server config"); return 1; }
    guard let trusting = TlsConfig.client(true, "ca.pem", ["http/1.1"]).ok_value() else { println("no client config"); return 1; }
    guard let listener = AsyncListener.bind("127.0.0.1", 0, 16).ok_value() else { return 1; }
    let port = listener.port();
    let serving = spawn echo_server(listener, server_config, 5);

    // A verified connection by name, with ALPN.
    switch await TlsStream.connect("localhost", port, trusting) {
        case .ok(let tls):
            println(f"{tls.version()} {tls.alpn() ?? "none"}");
            await tls.write("hello tls");
            println(await read_all(tls, 9));
            // A megabyte crosses many TLS records and socket buffers.
            let big = "abcdefgh".repeat(131072);
            let writer = spawn tls.write(big);
            let echoed = await read_all(tls, big.len() as i32);
            await writer;
            println(f"{echoed.len()} {echoed.equals(big.uppercased())}");
            await tls.close();
        case .err(let error): println(error.message);
    }
    // The certificate also names 127.0.0.1.
    switch await TlsStream.connect("127.0.0.1", port, trusting) {
        case .ok(let tls): await tls.write("ip"); println(await read_all(tls, 2)); await tls.close();
        case .err(let error): println(error.message);
    }
    // The system's trusted certificates do not include the test CA.
    switch await TlsStream.connect("localhost", port) {
        case .ok(let tls): println("unexpectedly trusted");
        case .err(let error): println(error.message);
    }
    // A name the certificate does not cover.
    guard let socket = (await AsyncStream.connect("127.0.0.1", port)).ok_value() else { return 2; }
    switch await TlsStream.client(socket, "example.com", trusting) {
        case .ok(let tls): println("unexpectedly matched");
        case .err(let error): println(error.message);
    }
    // Without verification the handshake succeeds.
    guard let lax = TlsConfig.client(false).ok_value() else { return 3; }
    switch await TlsStream.connect("localhost", port, lax) {
        case .ok(let tls): await tls.write("lax"); println(await read_all(tls, 3)); await tls.close();
        case .err(let error): println(error.message);
    }
    println(f"{await serving} clients rejected the certificate");

    switch TlsConfig.server("missing.pem", "key.pem") {
        case .ok(let config): println("unexpected config");
        case .err(let error): println(error.message);
    }
    switch TlsConfig.server("cert.pem", "ca.pem") {
        case .ok(let config): println("unexpected config");
        case .err(let error): println(error.message);
    }

    // https through std.http.
    guard let https = HttpServer.bind("127.0.0.1", 0, server_config).ok_value() else { return 4; }
    let base = f"https://localhost:{https.port()}";
    let http_serving = spawn https.serve(handle, 3);
    let client = HttpClient.new();
    client.tls = trusting;
    switch await client.get(base + "/hello") {
        case .ok(let response): println(f"{response.status} {response.body}");
        case .err(let error): println(error.to_string());
    }
    switch await client.post(base + "/size", "x".repeat(300000)) {
        case .ok(let response): println(f"{response.status} {response.body}");
        case .err(let error): println(error.to_string());
    }
    // The default client does not trust the test CA.
    switch await http_get(base + "/hello") {
        case .ok(let response): println("unexpectedly trusted");
        case .err(let error): println(error.to_string().replace(f":{https.port()}", ":PORT"));
    }
    switch await http_serving { case .ok(let n): println(f"served {n} connections"); case .err(let e): println(e.to_string()); }
    0
}
