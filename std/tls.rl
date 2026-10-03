// Standard library: TLS connections, as used by https.
//
//     switch await TlsStream.connect("example.com", 443) {
//         case .ok(let tls):
//             await tls.write("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n");
//             ...
//         case .err(let error): eprintln(error.to_string());
//     }
//
// TLS uses OpenSSL 3 (or 1.1.1), loaded the first time a configuration is
// created, so programs that never use TLS do not need it installed. The
// library is searched in the usual places (Homebrew and MacPorts on macOS,
// libssl.so.3 elsewhere); ROLANG_LIBSSL names it explicitly. Clients verify
// the server's certificate and host name against the system's trusted
// certificates unless configured otherwise. TLS 1.2 is the oldest version
// accepted.
import "task.rl"
import "string.rl"
import "result.rl"
import "vec.rl"
import "range.rl"
import "async_io.rl"

pub extern "C" def rt_tls_context_new(server: i32, verify: i32, ca_file: String, certificate: String, key: String, alpn: String) -> RawPtr;
pub extern "C" def rt_tls_context_free(context: RawPtr) -> Void;
pub extern "C" def rt_tls_failure() -> RawPtr;
pub extern "C" def rt_tls_session_new(context: RawPtr, stream: RawPtr, host: String, server: i32) -> RawPtr;
pub extern "C" def rt_tls_session_free(session: RawPtr) -> Void;
pub extern "C" def rt_tls_handshake(session: RawPtr) -> i32;
pub extern "C" def rt_tls_read(session: RawPtr, limit: i32, status: RawPtr) -> RawPtr;
pub extern "C" def rt_tls_write(session: RawPtr, data: String, offset: i32, status: RawPtr) -> i32;
pub extern "C" def rt_tls_shutdown(session: RawPtr) -> i32;
pub extern "C" def rt_tls_session_error(session: RawPtr) -> RawPtr;
pub extern "C" def rt_tls_alpn(session: RawPtr) -> RawPtr;
pub extern "C" def rt_tls_version(session: RawPtr) -> RawPtr;
pub extern "C" def rt_tls_wait_start(session: RawPtr, writable: i32) -> RawPtr;

pub struct TlsError {
    pub let message: String;
    // The peer ended the connection without TLS close_notify, so an attacker
    // may have cut the data short. Protocols that frame their messages (HTTP
    // with Content-Length) can treat this as the end of the stream.
    pub let truncated: Bool = false;
    pub def to_string() -> String { self.message }
}

def tls_failure() -> TlsError {
    unsafe { return TlsError { message: String.from_handle(rt_tls_failure()) }; }
}

// Settings for connections: trusted certificates and ALPN protocols for
// clients, the certificate and private key for servers. One configuration
// serves any number of connections.
pub struct TlsConfig {
    var handle: RawPtr;
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_tls_context_free(handle);
        }
    }
    // Verifies servers against the system's trusted certificates, or only
    // against the PEM certificates in `ca_file`. `verify: false` accepts any
    // certificate and is only safe for testing. `alpn` offers protocols such
    // as "h2" and "http/1.1", in order of preference.
    pub static def client(verify: Bool = true, ca_file: String = "", alpn: Vec<String> = Vec<String>.new()) -> Result<TlsConfig, TlsError> {
        var check = 0; if verify { check = 1; }
        unsafe {
            let handle = rt_tls_context_new(0, check, ca_file, "", "", join_protocols(alpn));
            if (handle as i64) == 0 { return Result<TlsConfig, TlsError>.err(error: tls_failure()); }
            return Result<TlsConfig, TlsError>.ok(value: TlsConfig { handle });
        }
    }
    // Presents the PEM certificate chain in `certificate` (the server's own
    // certificate first) with the PEM private key in `key`. With `alpn`, the
    // first of these protocols that the client also offers is selected.
    pub static def server(certificate: String, key: String, alpn: Vec<String> = Vec<String>.new()) -> Result<TlsConfig, TlsError> {
        unsafe {
            let handle = rt_tls_context_new(1, 0, "", certificate, key, join_protocols(alpn));
            if (handle as i64) == 0 { return Result<TlsConfig, TlsError>.err(error: tls_failure()); }
            return Result<TlsConfig, TlsError>.ok(value: TlsConfig { handle });
        }
    }
    pub unsafe def raw_handle() -> RawPtr { return self.handle; }
}

def join_protocols(names: Vec<String>) -> String {
    var out = "";
    for index in 0..<names.len() { if index > 0 { out = out + ","; } out = out + names[index]; }
    out
}

// An encrypted connection over a TCP stream.
pub struct TlsStream {
    var handle: RawPtr;
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_tls_session_free(handle);
        }
    }

    // Connects to `host` and completes the handshake; the server's
    // certificate must be valid for `host` (a name or an IP address).
    pub static def connect(host: String, port: i32, config: TlsConfig? = nil) async -> Result<TlsStream, TlsError> {
        switch await AsyncStream.connect(host, port) {
            case .ok(let stream): return await TlsStream.client(stream, host, config);
            case .err(let code): return Result<TlsStream, TlsError>.err(error: TlsError { message: f"cannot connect to {host}:{port}: {os_error_message(code)}" });
        }
    }
    // Starts TLS as the client on a connected stream, as after STARTTLS.
    pub static def client(stream: AsyncStream, host: String, config: TlsConfig? = nil) async -> Result<TlsStream, TlsError> {
        var settings = config;
        if settings == nil {
            switch TlsConfig.client() {
                case .ok(let created): settings = created;
                case .err(let error): return Result<TlsStream, TlsError>.err(error: error);
            }
        }
        guard let chosen = settings else { return Result<TlsStream, TlsError>.err(error: tls_failure()); }
        var session: TlsStream? = nil;
        unsafe {
            let handle = rt_tls_session_new(chosen.raw_handle(), stream.raw_handle(), host, 0);
            if (handle as i64) != 0 { session = TlsStream { handle }; }
        }
        guard let created = session else { return Result<TlsStream, TlsError>.err(error: tls_failure()); }
        await created.handshake()
    }
    // Accepts TLS as the server on a connected stream.
    pub static def server(stream: AsyncStream, config: TlsConfig) async -> Result<TlsStream, TlsError> {
        var session: TlsStream? = nil;
        unsafe {
            let handle = rt_tls_session_new(config.raw_handle(), stream.raw_handle(), "", 1);
            if (handle as i64) != 0 { session = TlsStream { handle }; }
        }
        guard let created = session else { return Result<TlsStream, TlsError>.err(error: tls_failure()); }
        await created.handshake()
    }

    def handshake() async -> Result<TlsStream, TlsError> {
        while true {
            var status: i32 = 0;
            unsafe { status = rt_tls_handshake(self.handle); }
            if status == 0 { return Result<TlsStream, TlsError>.ok(value: self); }
            if status < 0 { return Result<TlsStream, TlsError>.err(error: self.error()); }
            if let problem = await self.wait(status) { return Result<TlsStream, TlsError>.err(error: problem); }
        }
        Result<TlsStream, TlsError>.err(error: self.error())
    }
    // Waits until the socket is readable (status 1) or writable (status 2).
    def wait(status: i32) async -> TlsError? {
        var result: i32 = 0;
        unsafe {
            let operation = Task<i32>.from_handle(rt_tls_wait_start(self.handle, status - 1));
            result = await operation;
        }
        if result < 0 { return TlsError { message: os_error_message(-result) }; }
        nil
    }
    def error() -> TlsError {
        unsafe { return TlsError { message: String.from_handle(rt_tls_session_error(self.handle)) }; }
    }

    // Decrypted bytes, at most `limit`; empty at the end of the stream. An
    // end without close_notify is an error whose `truncated` is true.
    pub def read(limit: i32 = 65536) async -> Result<String, TlsError> {
        while true {
            var status: i32 = 0;
            var data = "";
            unsafe { data = String.from_handle(rt_tls_read(self.handle, limit, status as RawPtr)); }
            if status == 0 { return Result<String, TlsError>.ok(value: data); }
            if status == 4 { return Result<String, TlsError>.err(error: TlsError { message: "connection closed without TLS close_notify; the data may be truncated", truncated: true }); }
            if status < 0 { return Result<String, TlsError>.err(error: self.error()); }
            if let problem = await self.wait(status) { return Result<String, TlsError>.err(error: problem); }
        }
        Result<String, TlsError>.err(error: self.error())
    }
    // Completes after all of `data` is written; the result is its length.
    pub def write(data: String) async -> Result<i32, TlsError> {
        let total = data.len() as i32;
        var offset = 0;
        while offset < total {
            var status: i32 = 0;
            var written: i32 = 0;
            unsafe { written = rt_tls_write(self.handle, data, offset, status as RawPtr); }
            offset += written;
            if status < 0 { return Result<i32, TlsError>.err(error: self.error()); }
            if status > 0 { if let problem = await self.wait(status) { return Result<i32, TlsError>.err(error: problem); } }
        }
        Result<i32, TlsError>.ok(value: total)
    }
    // Tells the peer no more data follows (TLS close_notify). The connection
    // itself closes when the stream is released.
    pub def close() async -> Void {
        while true {
            var status: i32 = 0;
            unsafe { status = rt_tls_shutdown(self.handle); }
            if status == 0 { return; }
            if let problem = await self.wait(status) { return; }
        }
    }

    // The protocol chosen by ALPN, if any.
    pub def alpn() -> String? {
        var chosen = "";
        unsafe { chosen = String.from_handle(rt_tls_alpn(self.handle)); }
        if chosen.len() == 0 { return nil; }
        chosen
    }
    // The negotiated version, such as "TLSv1.3".
    pub def version() -> String {
        unsafe { return String.from_handle(rt_tls_version(self.handle)); }
    }
}
