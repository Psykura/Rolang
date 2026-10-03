// Standard library: HTTP/1.1 clients and servers over TCP.
//
//     switch await http_get("http://example.com/") {
//         case .ok(let response): println(f"{response.status} {response.body.len()} bytes");
//         case .err(let error): eprintln(error.to_string());
//     }
//
//     guard let server = HttpServer.bind("127.0.0.1", 8080).ok_value() else { return 1; }
//     await server.serve((request) async -> {
//         if request.path().equals("/hello") { return HttpResponse.text("hi"); }
//         HttpResponse.text("not found", 404)
//     });
//
// Bodies are binary-safe strings. Requests and responses carry their length
// (or use chunked encoding); clients follow up to five redirects. https URLs
// need TLS, which is not available yet.
import "string.rl"
import "vec.rl"
import "dict.rl"
import "range.rl"
import "result.rl"
import "task.rl"
import "string_builder.rl"
import "async_io.rl"
import "json.rl"
import "time.rl"

pub struct HttpError {
    pub let message: String;
    pub def to_string() -> String { self.message }
}

def http_error<T>(message: String) -> Result<T, HttpError> { Result<T, HttpError>.err(error: HttpError { message }) }

// ---- URLs ----

pub struct Url {
    pub let scheme: String;
    pub let host: String;
    pub let port: i32;
    // Percent-encoded path, at least "/".
    pub let path: String;
    // Raw query without the "?", or "".
    pub let query: String;

    // An absolute http or https URL; nil when malformed. The fragment is dropped.
    pub static def parse(text: String) -> Url? {
        let scheme_end = text.find("://");
        if scheme_end <= 0 { return nil; }
        let scheme = text.substring(0, scheme_end).lowercased();
        if !scheme.equals("http") && !scheme.equals("https") { return nil; }
        var rest = text.substring(scheme_end + 3, (text.len() as i32) - scheme_end - 3);
        let hash = rest.find("#"); if hash >= 0 { rest = rest.substring(0, hash); }
        var authority = rest; var target = "/";
        let slash = rest.find("/"); let question = rest.find("?");
        var cut = slash; if cut < 0 || (question >= 0 && question < cut) { cut = question; }
        if cut >= 0 { authority = rest.substring(0, cut); target = rest.substring(cut, (rest.len() as i32) - cut); }
        if target.starts_with("?") { target = "/" + target; }
        if authority.find("@") >= 0 { return nil; }
        var host = authority; var port = 80; if scheme.equals("https") { port = 443; }
        if authority.starts_with("[") {
            let close = authority.find("]");
            if close < 0 { return nil; }
            host = authority.substring(1, close - 1);
            let after = authority.substring(close + 1, (authority.len() as i32) - close - 1);
            if after.len() > 0 {
                if !after.starts_with(":") { return nil; }
                guard let number = parse_port(after.substring(1, (after.len() as i32) - 1)) else { return nil; }
                port = number;
            }
        } else {
            let colon = authority.find(":");
            if colon >= 0 {
                host = authority.substring(0, colon);
                guard let number = parse_port(authority.substring(colon + 1, (authority.len() as i32) - colon - 1)) else { return nil; }
                port = number;
            }
        }
        if host.len() == 0 { return nil; }
        var path = target; var query = "";
        let mark = target.find("?");
        if mark >= 0 { path = target.substring(0, mark); query = target.substring(mark + 1, (target.len() as i32) - mark - 1); }
        Url { scheme, host: host.lowercased(), port, path, query }
    }
    // The request target: path and query.
    pub def target() -> String {
        if self.query.len() == 0 { return self.path; }
        self.path + "?" + self.query
    }
    // The Host header value.
    pub def authority() -> String {
        var host = self.host; if host.find(":") >= 0 { host = "[" + host + "]"; }
        let default_port = (self.scheme.equals("http") && self.port == 80) || (self.scheme.equals("https") && self.port == 443);
        if default_port { return host; }
        f"{host}:{self.port}"
    }
    // `location` relative to this URL: absolute, or an absolute or relative path.
    pub def join(location: String) -> Url? {
        if location.find("://") > 0 { return Url.parse(location); }
        if location.starts_with("//") { return Url.parse(self.scheme + ":" + location); }
        let base = self.scheme + "://" + self.authority();
        if location.starts_with("/") { return Url.parse(base + location); }
        let last = self.path.rfind("/");
        var relative = location; var query = "";
        let mark = location.find("?");
        if mark >= 0 { relative = location.substring(0, mark); query = location.substring(mark, (location.len() as i32) - mark); }
        Url.parse(base + remove_dot_segments(self.path.substring(0, last + 1) + relative) + query)
    }
    pub def to_string() -> String { self.scheme + "://" + self.authority() + self.target() }
}

// RFC 3986 dot-segment removal: /a/b/../c becomes /a/c.
def remove_dot_segments(path: String) -> String {
    let kept = Vec<String>.new();
    let parts = path.split("/");
    for index in 0..<parts.len() {
        let part = parts[index];
        if part.equals(".") { if index == parts.len() - 1 { kept.push(""); } continue; }
        if part.equals("..") {
            if kept.len() > 1 { kept.pop(); }
            if index == parts.len() - 1 { kept.push(""); }
            continue;
        }
        kept.push(part);
    }
    var out = "";
    for index in 0..<kept.len() { if index > 0 { out += "/"; } out += kept[index]; }
    if !out.starts_with("/") { out = "/" + out; }
    out
}

def parse_port(text: String) -> i32? {
    if text.len() == 0 || text.len() > 5 { return nil; }
    for index in 0..<(text.len() as i32) { let byte = text.byte_at(index); if byte < 48 || byte > 57 { return nil; } }
    let port = text.to_i32();
    if port > 65535 { return nil; }
    port
}

// Percent-encodes everything except RFC 3986 unreserved characters.
pub def percent_encode(text: String) -> String {
    let hex = "0123456789ABCDEF";
    let out = StringBuilder.new();
    for index in 0..<(text.len() as i32) {
        let byte = text.byte_at(index);
        let unreserved = (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) ||
            byte == 45 || byte == 46 || byte == 95 || byte == 126;
        if unreserved { out.append_byte(byte as u8); }
        else { out.append("%" + hex.substring(byte / 16, 1) + hex.substring(byte % 16, 1)); }
    }
    out.to_string()
}

// Decodes %XX escapes (and '+' as a space when `form`); nil for a malformed escape.
pub def percent_decode(text: String, form: Bool = false) -> String? {
    let out = StringBuilder.new();
    let length = text.len() as i32;
    var index = 0;
    while index < length {
        let byte = text.byte_at(index);
        if byte == 43 && form { out.append(" "); index += 1; continue; }
        if byte != 37 { out.append_byte(byte as u8); index += 1; continue; }
        if index + 2 >= length { return nil; }
        let high = hex_digit(text.byte_at(index + 1)); let low = hex_digit(text.byte_at(index + 2));
        if high < 0 || low < 0 { return nil; }
        out.append_byte((high * 16 + low) as u8);
        index += 3;
    }
    out.to_string()
}

def hex_digit(byte: i32) -> i32 {
    if byte >= 48 && byte <= 57 { return byte - 48; }
    if byte >= 97 && byte <= 102 { return byte - 87; }
    if byte >= 65 && byte <= 70 { return byte - 55; }
    -1
}

// `a=1&b=two+words` as an ordered map; a repeated name keeps its last value.
pub def parse_query(query: String) -> Dict<String, String> {
    let out = Dict<String, String>.new();
    if query.len() == 0 { return out; }
    for part in query.split("&") {
        if part.len() == 0 { continue; }
        let equals = part.find("=");
        var name = part; var value = "";
        if equals >= 0 { name = part.substring(0, equals); value = part.substring(equals + 1, (part.len() as i32) - equals - 1); }
        out[percent_decode(name, true) ?? name] = percent_decode(value, true) ?? value;
    }
    out
}

// The inverse of parse_query.
pub def encode_query(values: Dict<String, String>) -> String {
    let parts = Vec<String>.new();
    for entry in values.entries() { parts.push(percent_encode(entry.key) + "=" + percent_encode(entry.value)); }
    var out = "";
    for index in 0..<parts.len() { if index > 0 { out += "&"; } out += parts[index]; }
    out
}

// ---- Messages ----

pub struct HttpHeader {
    pub let name: String;
    pub let value: String;
}

// Header fields in order; names compare case-insensitively.
pub struct HttpHeaders {
    let fields: Vec<HttpHeader>;

    pub static def new() -> HttpHeaders { HttpHeaders { fields: Vec<HttpHeader>.new() } }
    // The first value of `name`, or nil.
    pub def get(name: String) -> String? {
        let wanted = name.lowercased();
        for field in self.fields { if field.name.lowercased().equals(wanted) { return field.value; } }
        nil
    }
    pub def all(name: String) -> Vec<String> {
        let wanted = name.lowercased();
        let values = Vec<String>.new();
        for field in self.fields { if field.name.lowercased().equals(wanted) { values.push(field.value); } }
        values
    }
    pub def contains(name: String) -> Bool { self.get(name) != nil }
    pub def add(name: String, value: String) -> Void { self.fields.push(HttpHeader { name, value }); }
    // Replaces every value of `name`.
    pub def set(name: String, value: String) -> Void { self.remove(name); self.add(name, value); }
    pub def remove(name: String) -> Void {
        let wanted = name.lowercased();
        let kept = Vec<HttpHeader>.new();
        for field in self.fields { if !field.name.lowercased().equals(wanted) { kept.push(field); } }
        while self.fields.len() > 0 { self.fields.pop(); }
        for field in kept { self.fields.push(field); }
    }
    pub def entries() -> Vec<HttpHeader> { self.fields.slice(0..<self.fields.len()) }
    pub def len() -> i32 { self.fields.len() }
}

pub struct HttpRequest {
    pub var method: String;
    // The request target, e.g. "/search?q=rolang".
    pub var target: String;
    pub var headers: HttpHeaders;
    pub var body: String;
    pub var version: String = "HTTP/1.1";

    pub static def new(method: String, target: String = "/", body: String = "") -> HttpRequest {
        HttpRequest { method, target, headers: HttpHeaders.new(), body }
    }
    // The decoded path, without the query.
    pub def path() -> String {
        let mark = self.target.find("?");
        var path = self.target; if mark >= 0 { path = self.target.substring(0, mark); }
        percent_decode(path) ?? path
    }
    pub def query() -> Dict<String, String> {
        let mark = self.target.find("?");
        if mark < 0 { return Dict<String, String>.new(); }
        parse_query(self.target.substring(mark + 1, (self.target.len() as i32) - mark - 1))
    }
    pub def json() -> Result<Json, JsonError> { Json.parse(self.body) }
}

pub struct HttpResponse {
    pub var status: i32;
    pub var reason: String;
    pub var headers: HttpHeaders;
    pub var body: String;

    pub static def new(status: i32, body: String = "", content_type: String = "") -> HttpResponse {
        let response = HttpResponse { status, reason: status_reason(status), headers: HttpHeaders.new(), body };
        if content_type.len() > 0 { response.headers.set("Content-Type", content_type); }
        response
    }
    pub static def text(body: String, status: i32 = 200) -> HttpResponse { HttpResponse.new(status, body, "text/plain; charset=utf-8") }
    pub static def html(body: String, status: i32 = 200) -> HttpResponse { HttpResponse.new(status, body, "text/html; charset=utf-8") }
    pub static def json(value: Json, status: i32 = 200) -> HttpResponse { HttpResponse.new(status, value.to_string(), "application/json") }
    // A 3xx response pointing at `location`.
    pub static def redirect(location: String, status: i32 = 302) -> HttpResponse {
        let response = HttpResponse.new(status);
        response.headers.set("Location", location);
        response
    }
    // Status 200 to 299.
    pub def ok() -> Bool { self.status >= 200 && self.status < 300 }
    pub def json_body() -> Result<Json, JsonError> { Json.parse(self.body) }
}

pub def status_reason(status: i32) -> String {
    switch status {
        case 100: "Continue"; case 101: "Switching Protocols";
        case 200: "OK"; case 201: "Created"; case 202: "Accepted"; case 204: "No Content";
        case 301: "Moved Permanently"; case 302: "Found"; case 303: "See Other"; case 304: "Not Modified";
        case 307: "Temporary Redirect"; case 308: "Permanent Redirect";
        case 400: "Bad Request"; case 401: "Unauthorized"; case 403: "Forbidden"; case 404: "Not Found";
        case 405: "Method Not Allowed"; case 408: "Request Timeout"; case 409: "Conflict"; case 413: "Content Too Large";
        case 415: "Unsupported Media Type"; case 422: "Unprocessable Content"; case 429: "Too Many Requests";
        case 500: "Internal Server Error"; case 501: "Not Implemented"; case 502: "Bad Gateway";
        case 503: "Service Unavailable"; case 504: "Gateway Timeout";
        default: "";
    }
}

// ---- Wire format ----

// Bytes read from a stream, consumed as lines, fixed-size blocks or until EOF.
struct HttpReader {
    let stream: AsyncStream;
    var buffer: String;
    var eof: Bool;
    let max_body: i32;

    def fill() async -> Result<Bool, HttpError> {
        if self.eof { return Result<Bool, HttpError>.ok(value: false); }
        switch await self.stream.read(65536) {
            case .ok(let data):
                if data.len() == 0 { self.eof = true; return Result<Bool, HttpError>.ok(value: false); }
                self.buffer = self.buffer + data;
                return Result<Bool, HttpError>.ok(value: true);
            case .err(let code): return http_error(f"read failed: {os_error_message(code)}");
        }
    }
    // The header block up to the blank line; nil at a clean EOF before any byte.
    def head() async -> Result<String?, HttpError> {
        while true {
            let end = self.buffer.find("\r\n\r\n");
            if end >= 0 {
                let block = self.buffer.substring(0, end);
                self.buffer = self.buffer.substring(end + 4, (self.buffer.len() as i32) - end - 4);
                return Result<String?, HttpError>.ok(value: block);
            }
            if self.buffer.len() > 65536 { return http_error("header section exceeds 64 KiB"); }
            switch await self.fill() {
                case .ok(let more):
                    if !more {
                        if self.buffer.len() == 0 { let none: String? = nil; return Result<String?, HttpError>.ok(value: none); }
                        return http_error("connection closed in the middle of a header");
                    }
                case .err(let error): return Result<String?, HttpError>.err(error: error);
            }
        }
        http_error("unreachable")
    }
    def take(count: i32) async -> Result<String, HttpError> {
        if count > self.max_body { return http_error(f"body exceeds the {self.max_body}-byte limit"); }
        while self.buffer.len() < count {
            switch await self.fill() {
                case .ok(let more): if !more { return http_error("connection closed before the body was complete"); }
                case .err(let error): return Result<String, HttpError>.err(error: error);
            }
        }
        let data = self.buffer.substring(0, count);
        self.buffer = self.buffer.substring(count, (self.buffer.len() as i32) - count);
        Result<String, HttpError>.ok(value: data)
    }
    def line() async -> Result<String, HttpError> {
        while true {
            let end = self.buffer.find("\r\n");
            if end >= 0 {
                let text = self.buffer.substring(0, end);
                self.buffer = self.buffer.substring(end + 2, (self.buffer.len() as i32) - end - 2);
                return Result<String, HttpError>.ok(value: text);
            }
            if self.buffer.len() > 65536 { return http_error("line exceeds 64 KiB"); }
            switch await self.fill() {
                case .ok(let more): if !more { return http_error("connection closed in the middle of a line"); }
                case .err(let error): return Result<String, HttpError>.err(error: error);
            }
        }
        http_error("unreachable")
    }
    def rest() async -> Result<String, HttpError> {
        while true {
            if self.buffer.len() > self.max_body { return http_error(f"body exceeds the {self.max_body}-byte limit"); }
            switch await self.fill() {
                case .ok(let more): if !more { break; }
                case .err(let error): return Result<String, HttpError>.err(error: error);
            }
        }
        let data = self.buffer;
        self.buffer = "";
        Result<String, HttpError>.ok(value: data)
    }
    // A body framed by `headers`: chunked, Content-Length, or (for responses) until EOF.
    def body(headers: HttpHeaders, until_eof: Bool) async -> Result<String, HttpError> {
        if let encoding = headers.get("Transfer-Encoding") {
            if !encoding.lowercased().contains("chunked") { return http_error(f"unsupported transfer encoding '{encoding}'"); }
            let out = StringBuilder.new();
            while true {
                var size_line = "";
                switch await self.line() { case .ok(let text): size_line = text; case .err(let error): return Result<String, HttpError>.err(error: error); }
                let semicolon = size_line.find(";"); if semicolon >= 0 { size_line = size_line.substring(0, semicolon); }
                size_line = size_line.trim();
                if size_line.len() == 0 || size_line.len() > 7 { return http_error("invalid chunk size"); }
                var size = 0;
                for index in 0..<(size_line.len() as i32) {
                    let digit = hex_digit(size_line.byte_at(index));
                    if digit < 0 { return http_error("invalid chunk size"); }
                    size = size * 16 + digit;
                }
                if size == 0 {
                    // Trailer fields end with a blank line.
                    while true {
                        switch await self.line() { case .ok(let text): if text.len() == 0 { return Result<String, HttpError>.ok(value: out.to_string()); } case .err(let error): return Result<String, HttpError>.err(error: error); }
                    }
                }
                if (out.len() as i32) + size > self.max_body { return http_error(f"body exceeds the {self.max_body}-byte limit"); }
                switch await self.take(size + 2) {
                    case .ok(let chunk): out.append(chunk.substring(0, size));
                    case .err(let error): return Result<String, HttpError>.err(error: error);
                }
            }
        }
        if let length = headers.get("Content-Length") {
            let text = length.trim();
            if text.len() == 0 || text.len() > 10 { return http_error("invalid Content-Length"); }
            for index in 0..<(text.len() as i32) { let byte = text.byte_at(index); if byte < 48 || byte > 57 { return http_error("invalid Content-Length"); } }
            let size = text.to_i64();
            if size > (self.max_body as i64) { return http_error(f"body exceeds the {self.max_body}-byte limit"); }
            return await self.take(size as i32);
        }
        if until_eof { return await self.rest(); }
        Result<String, HttpError>.ok(value: "")
    }
}

// Header lines into fields; nil when one is malformed.
def parse_header_lines(lines: Vec<String>, from: i32) -> HttpHeaders? {
    let headers = HttpHeaders.new();
    for index in from..<lines.len() {
        let line = lines[index];
        let colon = line.find(":");
        if colon <= 0 { return nil; }
        let name = line.substring(0, colon);
        if name.find(" ") >= 0 || name.find("\t") >= 0 { return nil; }
        headers.add(name, line.substring(colon + 1, (line.len() as i32) - colon - 1).trim());
    }
    headers
}

def write_message(start: String, headers: HttpHeaders, body: String) -> String {
    let out = StringBuilder.new();
    out.append(start + "\r\n");
    for field in headers.entries() { out.append(field.name + ": " + field.value + "\r\n"); }
    out.append("\r\n");
    out.append(body);
    out.to_string()
}

// ---- Client ----

pub struct HttpClient {
    pub var follow_redirects: Bool;
    pub var max_body: i32;
    // Limit for each request and response exchange, including connecting.
    pub var timeout: Duration;
    // Sent with every request unless the request sets the same field.
    pub let headers: HttpHeaders;

    pub static def new() -> HttpClient {
        let headers = HttpHeaders.new();
        headers.set("User-Agent", "Rolang");
        headers.set("Accept", "*/*");
        HttpClient { follow_redirects: true, max_body: 67108864, timeout: Duration.seconds(30), headers }
    }

    pub def get(url: String) async -> Result<HttpResponse, HttpError> { await self.send(HttpRequest.new("GET"), url) }
    pub def post(url: String, body: String, content_type: String = "application/octet-stream") async -> Result<HttpResponse, HttpError> {
        let request = HttpRequest.new("POST", "/", body);
        request.headers.set("Content-Type", content_type);
        await self.send(request, url)
    }
    pub def post_json(url: String, value: Json) async -> Result<HttpResponse, HttpError> {
        await self.post(url, value.to_string(), "application/json")
    }

    // Sends `request` to `url`; the request's own target is replaced by the URL's.
    pub def send(request: HttpRequest, url: String) async -> Result<HttpResponse, HttpError> {
        guard let first = Url.parse(url) else { return http_error(f"invalid URL '{url}'"); }
        var target = first;
        var method = request.method; var body = request.body;
        var redirects = 0;
        while true {
            if target.scheme.equals("https") { return http_error("https needs TLS, which std.http does not support yet"); }
            var response = HttpResponse.new(0);
            let exchange = spawn self.exchange(method, target, request.headers, body);
            guard let outcome = await with_timeout(exchange, self.timeout) else {
                return http_error(f"no response from {target.authority()} within {self.timeout}");
            }
            switch outcome {
                case .ok(let received): response = received;
                case .err(let error): return Result<HttpResponse, HttpError>.err(error: error);
            }
            let redirect = response.status == 301 || response.status == 302 || response.status == 303 || response.status == 307 || response.status == 308;
            guard let location = response.headers.get("Location") else { return Result<HttpResponse, HttpError>.ok(value: response); }
            if !redirect || !self.follow_redirects { return Result<HttpResponse, HttpError>.ok(value: response); }
            redirects += 1;
            if redirects > 5 { return http_error("too many redirects"); }
            guard let next = target.join(location) else { return http_error(f"invalid redirect location '{location}'"); }
            target = next;
            // 303, and 301/302 after POST, continue with GET.
            if response.status == 303 || ((response.status == 301 || response.status == 302) && method.equals("POST")) { method = "GET"; body = ""; }
        }
        http_error("unreachable")
    }

    def exchange(method: String, url: Url, extra: HttpHeaders, body: String) async -> Result<HttpResponse, HttpError> {
        var connected: AsyncStream? = nil;
        switch await AsyncStream.connect(url.host, url.port) {
            case .ok(let stream): connected = stream;
            case .err(let code): return http_error(f"cannot connect to {url.authority()}: {os_error_message(code)}");
        }
        guard let connection = connected else { return http_error("connection failed"); }
        let headers = HttpHeaders.new();
        headers.set("Host", url.authority());
        for field in self.headers.entries() { if !extra.contains(field.name) { headers.add(field.name, field.value); } }
        for field in extra.entries() { headers.add(field.name, field.value); }
        headers.set("Connection", "close");
        if body.len() > 0 || method.equals("POST") || method.equals("PUT") || method.equals("PATCH") { headers.set("Content-Length", body.len().to_string()); }
        switch await connection.write(write_message(f"{method} {url.target()} HTTP/1.1", headers, body)) {
            case .ok(let count): {}
            case .err(let code): return http_error(f"write failed: {os_error_message(code)}");
        }
        let reader = HttpReader { stream: connection, buffer: "", eof: false, max_body: self.max_body };
        while true {
            var head = "";
            switch await reader.head() {
                case .ok(let block): if let text = block { head = text; } else { return http_error("connection closed before a response"); }
                case .err(let error): return Result<HttpResponse, HttpError>.err(error: error);
            }
            let lines = head.split("\r\n");
            let status_line = lines[0];
            let parts = status_line.split(" ");
            if parts.len() < 2 || !parts[0].starts_with("HTTP/1.") { return http_error(f"invalid status line '{status_line}'"); }
            let status = parts[1].to_i32();
            var reason = "";
            let space = status_line.find(" ");
            let second = status_line.substring(space + 1, (status_line.len() as i32) - space - 1).find(" ");
            if second >= 0 { reason = status_line.substring(space + 2 + second, (status_line.len() as i32) - space - 2 - second); }
            guard let fields = parse_header_lines(lines, 1) else { return http_error("invalid response header"); }
            // Informational responses precede the real one.
            if status >= 100 && status < 200 { continue; }
            let response = HttpResponse { status, reason, headers: fields, body: "" };
            if method.equals("HEAD") || status == 204 || status == 304 { return Result<HttpResponse, HttpError>.ok(value: response); }
            switch await reader.body(fields, true) {
                case .ok(let data): response.body = data;
                case .err(let error): return Result<HttpResponse, HttpError>.err(error: error);
            }
            return Result<HttpResponse, HttpError>.ok(value: response);
        }
        http_error("unreachable")
    }
}

pub def http_get(url: String) async -> Result<HttpResponse, HttpError> { await HttpClient.new().get(url) }
pub def http_post(url: String, body: String, content_type: String = "application/octet-stream") async -> Result<HttpResponse, HttpError> {
    await HttpClient.new().post(url, body, content_type)
}

// ---- Server ----

pub struct HttpServer {
    let listener: AsyncListener;
    pub var max_body: i32;
    // A connection is closed when a request's head or body takes longer,
    // including the wait for the next request on a keep-alive connection.
    pub var idle_timeout: Duration;

    // Listens on a numeric address; port zero picks a free port.
    pub static def bind(address: String, port: i32) -> Result<HttpServer, HttpError> {
        switch AsyncListener.bind(address, port, 128) {
            case .ok(let listener): return Result<HttpServer, HttpError>.ok(value: HttpServer { listener, max_body: 16777216, idle_timeout: Duration.seconds(60) });
            case .err(let code): return http_error(f"cannot listen on {address}:{port}: {os_error_message(code)}");
        }
    }
    pub def port() -> i32 { self.listener.port() }

    // Serves each connection in its own task, calling `handler` for every
    // request; keep-alive connections carry several requests. Runs forever,
    // or until `connections` connections have been accepted and finished.
    pub def serve(handler: (HttpRequest) async -> HttpResponse, connections: i32 = 0) async -> Result<i32, HttpError> {
        let running = Vec<Task<Void>>.new();
        var accepted = 0;
        while connections == 0 || accepted < connections {
            switch await self.listener.accept() {
                case .ok(let stream):
                    accepted += 1;
                    running.push(spawn serve_connection(stream, handler, self.max_body, self.idle_timeout));
                case .err(let code): return http_error(f"accept failed: {os_error_message(code)}");
            }
        }
        for task in running { await task; }
        Result<i32, HttpError>.ok(value: accepted)
    }
}

def serve_connection(stream: AsyncStream, handler: (HttpRequest) async -> HttpResponse, max_body: i32, idle: Duration) async -> Void {
    let reader = HttpReader { stream, buffer: "", eof: false, max_body };
    while true {
        var head = "";
        guard let received = await with_timeout(spawn reader.head(), idle) else { break; }
        switch received {
            case .ok(let block): if let text = block { head = text; } else { break; }
            case .err(let error): await respond(stream, HttpResponse.text(error.message, 400), false); break;
        }
        let lines = head.split("\r\n");
        let parts = lines[0].split(" ");
        if parts.len() != 3 || !parts[2].starts_with("HTTP/1.") {
            await respond(stream, HttpResponse.text("malformed request line", 400), false); break;
        }
        guard let headers = parse_header_lines(lines, 1) else { await respond(stream, HttpResponse.text("malformed header", 400), false); break; }
        let request = HttpRequest { method: parts[0], target: parts[1], headers, body: "", version: parts[2] };
        guard let body_result = await with_timeout(spawn reader.body(headers, false), idle) else {
            await respond(stream, HttpResponse.text("request body timed out", 408), false); break;
        }
        switch body_result {
            case .ok(let body): request.body = body;
            case .err(let error): await respond(stream, HttpResponse.text(error.message, 400), false); break;
        }
        let connection = (headers.get("Connection") ?? "").lowercased();
        let keep_alive = (request.version.equals("HTTP/1.1") && !connection.equals("close")) || connection.equals("keep-alive");
        let response = await handler(request);
        if !(await respond(stream, response, keep_alive, request.method.equals("HEAD"))) { break; }
        if !keep_alive { break; }
    }
    stream.shutdown_write();
}

def respond(stream: AsyncStream, response: HttpResponse, keep_alive: Bool, head_only: Bool = false) async -> Bool {
    let headers = HttpHeaders.new();
    for field in response.headers.entries() { headers.add(field.name, field.value); }
    if !headers.contains("Server") { headers.set("Server", "Rolang"); }
    headers.set("Content-Length", response.body.len().to_string());
    if keep_alive { headers.set("Connection", "keep-alive"); } else { headers.set("Connection", "close"); }
    var reason = response.reason; if reason.len() == 0 { reason = status_reason(response.status); }
    var body = response.body; if head_only { body = ""; }
    switch await stream.write(write_message(f"HTTP/1.1 {response.status} {reason}", headers, body)) {
        case .ok(let count): return true;
        case .err(let code): return false;
    }
}
