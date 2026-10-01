import "task.rl"
import "string.rl"
import "result.rl"

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

pub struct AsyncStream {
    var handle: RawPtr;
    // Numeric IPv4/IPv6 address. Name resolution is not performed.
    pub static def connect(address: String, port: i32) async -> Result<AsyncStream, i32> {
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
