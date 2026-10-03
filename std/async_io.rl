import "task.rl"
import "string.rl"
import "result.rl"
import "vec.rl"
import "range.rl"

pub extern "C" def rt_async_stream_pair(other: RawPtr) -> RawPtr;
pub extern "C" def rt_async_stream_adopt(fd: i32) -> RawPtr;
pub extern "C" def rt_async_stream_close(stream: RawPtr) -> Void;
pub extern "C" def rt_async_stream_shutdown(stream: RawPtr) -> i32;
pub extern "C" def rt_async_read_start(stream: RawPtr, limit: i32) -> RawPtr;
pub extern "C" def rt_async_write_start(stream: RawPtr, value: String) -> RawPtr;
pub extern "C" def rt_async_read_data(task: RawPtr) -> RawPtr;

pub extern "C" def rt_async_connect_start(address: String, port: i32) -> RawPtr;
pub extern "C" def rt_async_take_stream(task: RawPtr) -> RawPtr;
pub extern "C" def rt_async_listener_bind(address: String, port: i32, backlog: i32, out: RawPtr) -> i32;
pub extern "C" def rt_async_listener_port(listener: RawPtr) -> i32;
pub extern "C" def rt_async_accept_start(listener: RawPtr) -> RawPtr;
pub extern "C" def rt_net_resolve(host: String, error: RawPtr) -> RawPtr;
pub extern "C" def rt_udp_bind(address: String, port: i32, out: RawPtr) -> i32;
pub extern "C" def rt_udp_send_start(socket: RawPtr, data: String, address: String, port: i32) -> RawPtr;
pub extern "C" def rt_udp_receive_start(socket: RawPtr, limit: i32) -> RawPtr;
pub extern "C" def rt_udp_received_data(task: RawPtr) -> RawPtr;
pub extern "C" def rt_udp_received_address(task: RawPtr, port: RawPtr) -> RawPtr;
pub extern "C" def rt_socket_port(socket: RawPtr) -> i32;
pub extern "C" def rt_os_error_message(code: i32) -> RawPtr;

pub extern "C" def rt_errno_host_unreachable() -> i32;

// The errno value (EHOSTUNREACH) reported when a host name does not resolve.
pub def host_unreachable() -> i32 {
    unsafe { return rt_errno_host_unreachable(); }
}

// The operating system's description of an errno value, e.g. "Connection refused".
pub def os_error_message(code: i32) -> String {
    unsafe { return String.from_handle(rt_os_error_message(code)); }
}

// Numeric addresses for a host name or address text, IPv4 first. Blocks the
// scheduler thread while the system resolver runs; the error is its message.
pub def resolve(host: String) -> Result<Vec<String>, String> {
    unsafe {
        var code: i32 = 0;
        let text = String.from_handle(rt_net_resolve(host, code as RawPtr));
        if code != 0 { return Result.err(error: text); }
        if text.len() == 0 { return Result.err(error: "no addresses"); }
        return Result.ok(value: text.split("\n"));
    }
}

pub struct AsyncStream {
    var handle: RawPtr;
    // Connects to a host name or numeric IPv4/IPv6 address, trying each
    // resolved address in turn. A name that does not resolve fails with
    // EHOSTUNREACH; resolve() reports the resolver's reason.
    pub static def connect(host: String, port: i32) async -> Result<AsyncStream, i32> {
        var addresses = Vec<String>.new();
        switch resolve(host) {
            case .ok(let found): addresses = found;
            case .err(let message): return Result.err(error: host_unreachable());
        }
        var last = host_unreachable();
        for address in addresses {
            switch await AsyncStream.connect_address(address, port) {
                case .ok(let stream): return Result.ok(value: stream);
                case .err(let code): last = code;
            }
        }
        Result.err(error: last)
    }
    // Connects to one numeric address without name resolution.
    pub static def connect_address(address: String, port: i32) async -> Result<AsyncStream, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_async_connect_start(address, port));
            let status = await operation;
            if status < 0 { return Result.err(error: -status); }
            return Result.ok(value: AsyncStream { handle: rt_async_take_stream(operation.raw_handle()) });
        }
    }

    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_async_stream_close(handle);
        }
    }

    // Transfers ownership of a socket fd, including on failure. The caller
    // must stop accessing the fd; the runtime makes it nonblocking.
    pub unsafe static def adopt(fd: i32) -> AsyncStream? {
        unsafe {
            let handle = rt_async_stream_adopt(fd);
            if (handle as i64) == 0 { return nil; }
            return AsyncStream { handle: handle };
        }
    }

    // One read, at most limit bytes. Empty success means EOF (or limit == 0).
    pub def read(limit: i32) async -> Result<String, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_async_read_start(self.handle, limit));
            let count = await operation;
            if count < 0 { return Result.err(error: -count); }
            return Result.ok(value: String.from_handle(rt_async_read_data(operation.raw_handle())));
        }
    }

    // Completes after all bytes are written. Errors are positive POSIX errno;
    // the peer may already have received a prefix when an error occurs.
    pub def write(value: String) async -> Result<i32, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_async_write_start(self.handle, value));
            let count = await operation;
            if count < 0 { return Result.err(error: -count); }
            return Result.ok(value: count);
        }
    }

    pub def shutdown_write() -> i32 {
        unsafe { return rt_async_stream_shutdown(self.handle); }
    }
}

pub struct AsyncPipe {
    pub var first: AsyncStream;
    pub var second: AsyncStream;

    // A full-duplex local socket pair for communicating between tasks.
    pub static def create() -> AsyncPipe? {
        unsafe {
            var other: RawPtr;
            let first = rt_async_stream_pair(other as RawPtr);
            if (first as i64) == 0 { return nil; }
            return AsyncPipe {
                first: AsyncStream { handle: first },
                second: AsyncStream { handle: other }
            };
        }
    }
}

// Owns a nonblocking TCP listening socket. Pending accepts retain it.
pub struct AsyncListener {
    var handle: RawPtr;
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_async_stream_close(handle);
        }
    }
    // Port zero asks the OS to select an available port.
    pub static def bind(address: String, port: i32, backlog: i32) -> Result<AsyncListener, i32> {
        unsafe {
            var handle: RawPtr;
            let status = rt_async_listener_bind(address, port, backlog, handle as RawPtr);
            if status < 0 { return Result.err(error: -status); }
            return Result.ok(value: AsyncListener { handle: handle });
        }
    }
    pub def port() -> i32 {
        unsafe { return rt_async_listener_port(self.handle); }
    }
    pub def accept() async -> Result<AsyncStream, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_async_accept_start(self.handle));
            let status = await operation;
            if status < 0 { return Result.err(error: -status); }
            return Result.ok(value: AsyncStream { handle: rt_async_take_stream(operation.raw_handle()) });
        }
    }
}

// One received datagram and its sender.
pub struct Datagram {
    pub let data: String;
    pub let address: String;
    pub let port: i32;
}

// A nonblocking UDP socket. Datagrams are binary-safe strings of at most
// 65507 bytes.
pub struct UdpSocket {
    var handle: RawPtr;
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_async_stream_close(handle);
        }
    }
    // Binds a numeric address; port zero asks the OS for a free port.
    pub static def bind(address: String, port: i32) -> Result<UdpSocket, i32> {
        unsafe {
            var handle: RawPtr;
            let status = rt_udp_bind(address, port, handle as RawPtr);
            if status < 0 { return Result.err(error: -status); }
            return Result.ok(value: UdpSocket { handle: handle });
        }
    }
    pub def port() -> i32 {
        unsafe { return rt_socket_port(self.handle); }
    }
    // Sends one datagram to a numeric address; the result is the byte count.
    pub def send_to(data: String, address: String, port: i32) async -> Result<i32, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_udp_send_start(self.handle, data, address, port));
            let count = await operation;
            if count < 0 { return Result.err(error: -count); }
            return Result.ok(value: count);
        }
    }
    // Waits for one datagram; longer datagrams are truncated to `limit` bytes.
    pub def receive(limit: i32 = 65536) async -> Result<Datagram, i32> {
        unsafe {
            let operation = Task<i32>.from_handle(rt_udp_receive_start(self.handle, limit));
            let count = await operation;
            if count < 0 { return Result.err(error: -count); }
            var port: i32 = 0;
            let address = String.from_handle(rt_udp_received_address(operation.raw_handle(), port as RawPtr));
            return Result.ok(value: Datagram { data: String.from_handle(rt_udp_received_data(operation.raw_handle())), address, port });
        }
    }
}
