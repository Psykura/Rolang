// Standard library: values that cross threads, for `parallel def` functions.
//
//     parallel def checksum(data: Vec<u8>) async -> u64 { ... }   // runs on a worker thread
//     let sums = [spawn checksum(a), spawn checksum(b)];          // in parallel
//
// A parallel function runs on a pool of worker threads (ROLANG_WORKERS, else
// one per processor), each with its own scheduler, so it may await, spawn
// tasks and do I/O there. Threads share no objects: arguments and results
// are Sendable values, encoded on one thread and decoded into new objects on
// the other. Numbers, Bool, String, Vec, Dict, optionals and Result of
// Sendable values are Sendable; a struct or enum declares `: Sendable` to
// derive the encoding from its fields (which must be Sendable too). A
// Channel<T> passes Sendable values between threads while they run.
import "string.rl"
import "vec.rl"
import "dict.rl"
import "range.rl"
import "result.rl"
import "task.rl"

pub extern "C" def rt_send_buffer_new() -> RawPtr;
pub extern "C" def rt_send_buffer_free(buffer: RawPtr) -> Void;
pub extern "C" def rt_send_put_i64(buffer: RawPtr, value: i64) -> Void;
pub extern "C" def rt_send_put_f64(buffer: RawPtr, value: f64) -> Void;
pub extern "C" def rt_send_put_string(buffer: RawPtr, value: String) -> Void;
pub extern "C" def rt_send_enter(buffer: RawPtr) -> Void;
pub extern "C" def rt_send_leave(buffer: RawPtr) -> Void;
pub extern "C" def rt_send_get_i64(buffer: RawPtr) -> i64;
pub extern "C" def rt_send_get_f64(buffer: RawPtr) -> f64;
pub extern "C" def rt_send_get_string(buffer: RawPtr) -> RawPtr;
pub extern "C" def rt_parallel_workers() -> i32;
pub extern "C" def rt_parallel_submit(start: RawPtr, arguments: RawPtr) -> RawPtr;
pub extern "C" def rt_parallel_arguments(job: RawPtr) -> RawPtr;
pub extern "C" def rt_parallel_complete(job: RawPtr, result: RawPtr) -> Void;
pub extern "C" def rt_parallel_result(task: RawPtr) -> RawPtr;
pub extern "C" def rt_parallel_on_worker() -> i32;
pub extern "C" def rt_task_detach(task: RawPtr) -> Void;
pub extern "C" def rt_channel_new(capacity: i64) -> RawPtr;
pub extern "C" def rt_channel_release(channel: RawPtr) -> Void;
pub extern "C" def rt_channel_share(channel: RawPtr) -> i64;
pub extern "C" def rt_channel_from_shared(id: i64) -> RawPtr;
pub extern "C" def rt_channel_try_send(channel: RawPtr, writer: RawPtr) -> i32;
pub extern "C" def rt_channel_try_receive(channel: RawPtr) -> RawPtr;
pub extern "C" def rt_channel_drained(channel: RawPtr) -> i32;
pub extern "C" def rt_channel_closed(channel: RawPtr) -> i32;
pub extern "C" def rt_channel_len(channel: RawPtr) -> i64;
pub extern "C" def rt_channel_close(channel: RawPtr) -> Void;
pub extern "C" def rt_channel_wait(channel: RawPtr, receiving: i32) -> RawPtr;

// A value that can be copied to another thread.
pub protocol Sendable {
    def send_encode(out: SendWriter) -> Void;
    static def send_decode(input: SendReader) -> Self;
}

// Bytes being written for another thread.
pub struct SendWriter {
    var handle: RawPtr;
    pub static def new() -> SendWriter { unsafe { return SendWriter { handle: rt_send_buffer_new() }; } }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_send_buffer_free(handle);
        }
    }
    pub def put_int(value: i64) -> Void { unsafe { rt_send_put_i64(self.handle, value); } }
    pub def put_float(value: f64) -> Void { unsafe { rt_send_put_f64(self.handle, value); } }
    pub def put_bool(value: Bool) -> Void { var bit: i64 = 0; if value { bit = 1; } self.put_int(bit); }
    pub def put_string(value: String) -> Void { unsafe { rt_send_put_string(self.handle, value); } }
    // Brackets a nested value; a cycle fails instead of encoding forever.
    pub def enter() -> Void { unsafe { rt_send_enter(self.handle); } }
    pub def leave() -> Void { unsafe { rt_send_leave(self.handle); } }
    // The buffer, handed over: the writer is empty afterwards.
    pub unsafe def take() -> RawPtr {
        let handle = self.handle;
        unsafe { self.handle = rt_send_buffer_new(); }
        return handle;
    }
}

// Bytes received from another thread.
pub struct SendReader {
    var handle: RawPtr;
    pub unsafe static def from_handle(handle: RawPtr) -> SendReader { return SendReader { handle: handle }; }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_send_buffer_free(handle);
        }
    }
    pub def int() -> i64 { unsafe { return rt_send_get_i64(self.handle); } }
    pub def float() -> f64 { unsafe { return rt_send_get_f64(self.handle); } }
    pub def bool() -> Bool { self.int() != 0 }
    pub def string() -> String { unsafe { return String.from_handle(rt_send_get_string(self.handle)); } }
}

pub def send_encode_value<T: Sendable>(value: T, out: SendWriter) -> Void { value.send_encode(out); }
pub def send_decode_value<T: Sendable>(input: SendReader) -> T { T.send_decode(input) }

// The number of worker threads (starting them).
pub def parallel_workers() -> i32 { unsafe { return rt_parallel_workers(); } }
// Whether this code runs on a worker thread.
pub def on_worker_thread() -> Bool { unsafe { return rt_parallel_on_worker() != 0; } }

// Used by `parallel def`: runs `start` on a worker with the encoded arguments
// and returns the encoded result.
pub def __parallel_call(start: (RawPtr) -> Void, arguments: SendWriter) async -> SendReader {
    unsafe {
        let job = Task<i32>.from_handle(rt_parallel_submit(start as RawPtr, arguments.take()));
        await job;
        return SendReader.from_handle(rt_parallel_result(job.raw_handle()));
    }
}
// Used by `parallel def` on the worker: starts `run` as a task that outlives this call.
pub def __parallel_start(task: Task<Void>) -> Void {
    unsafe { rt_task_detach(task.raw_handle()); }
}
pub def __parallel_arguments(job: RawPtr) -> SendReader {
    unsafe { return SendReader.from_handle(rt_parallel_arguments(job)); }
}
pub def __parallel_finish(job: RawPtr, result: SendWriter) -> Void {
    unsafe { rt_parallel_complete(job, result.take()); }
}

// A queue of Sendable values that any thread holding it can use: a channel
// passed to a parallel function is the same channel there.
//
//     let results = Channel<i64>.new();
//     for part in parts { spawn sum_into(part, results); }   // parallel def sum_into(.., out: Channel<i64>)
//
// Values are copied in when sent and out when received. `send` waits while a
// bounded channel is full; `receive` waits while it is empty and returns nil
// once it is closed and empty.
pub struct Channel<T> {
    var handle: RawPtr;
    // An unbounded channel.
    pub static def new() -> Channel<T> { unsafe { return Channel<T> { handle: rt_channel_new(0) }; } }
    // A channel holding at most `capacity` values (at least 1).
    pub static def bounded(capacity: i64) -> Channel<T> {
        var limit = capacity;
        if limit < 1 { limit = 1; }
        unsafe { return Channel<T> { handle: rt_channel_new(limit) }; }
    }
    pub def __release__() -> Void {
        unsafe {
            let handle = self.handle;
            self.handle = 0 as RawPtr;
            rt_channel_release(handle);
        }
    }
    // No more sends; values already sent can still be received.
    pub def close() -> Void { unsafe { rt_channel_close(self.handle); } }
    pub def is_closed() -> Bool { unsafe { return rt_channel_closed(self.handle) != 0; } }
    // Values sent and not received yet.
    pub def len() -> i64 { unsafe { return rt_channel_len(self.handle); } }
}
pub extension<T> Channel<T> {
    // Waits for room; false when the channel is closed.
    pub def send(value: T) async -> Bool where T: Sendable {
        let out = SendWriter.new();
        value.send_encode(out);
        while true {
            unsafe {
                let status = rt_channel_try_send(self.handle, out.handle);
                if status != 0 { return status > 0; }
                let wait = rt_channel_wait(self.handle, 0);
                if (wait as i64) != 0 { await Task<i32>.from_handle(wait); }
            }
        }
        false
    }
    // Sends when there is room now; false when full or closed.
    pub def try_send(value: T) -> Bool where T: Sendable {
        let out = SendWriter.new();
        value.send_encode(out);
        unsafe { return rt_channel_try_send(self.handle, out.handle) > 0; }
    }
    // Waits for a value; nil once the channel is closed and empty.
    pub def receive() async -> T? where T: Sendable {
        while true {
            if let value = self.try_receive() { return value; }
            unsafe {
                if rt_channel_drained(self.handle) != 0 { let none: T? = nil; return none; }
                let wait = rt_channel_wait(self.handle, 1);
                if (wait as i64) != 0 { await Task<i32>.from_handle(wait); }
            }
        }
        let none: T? = nil;
        none
    }
    // A value if one is waiting.
    pub def try_receive() -> T? where T: Sendable {
        unsafe {
            let handle = rt_channel_try_receive(self.handle);
            if (handle as i64) == 0 { let none: T? = nil; return none; }
            let input = SendReader.from_handle(handle);
            let some: T? = T.send_decode(input);
            return some;
        }
    }
}
pub extension<T> Channel<T>: Sendable {
    pub def send_encode(out: SendWriter) -> Void { unsafe { out.put_int(rt_channel_share(self.handle)); } }
    pub static def send_decode(input: SendReader) -> Channel<T> {
        unsafe { return Channel<T> { handle: rt_channel_from_shared(input.int()) }; }
    }
}

pub extension i64: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self); }
    pub static def send_decode(input: SendReader) -> i64 { input.int() }
}
pub extension i32: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> i32 { input.int() as i32 }
}
pub extension i16: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> i16 { input.int() as i16 }
}
pub extension i8: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> i8 { input.int() as i8 }
}
pub extension u64: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> u64 { input.int() as u64 }
}
pub extension u32: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> u32 { input.int() as u32 }
}
pub extension u16: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> u16 { input.int() as u16 }
}
pub extension u8: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_int(self as i64); }
    pub static def send_decode(input: SendReader) -> u8 { input.int() as u8 }
}
pub extension f64: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_float(self); }
    pub static def send_decode(input: SendReader) -> f64 { input.float() }
}
pub extension f32: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_float(self as f64); }
    pub static def send_decode(input: SendReader) -> f32 { input.float() as f32 }
}
pub extension Bool: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_bool(self); }
    pub static def send_decode(input: SendReader) -> Bool { input.bool() }
}
pub extension String: Sendable {
    pub def send_encode(out: SendWriter) -> Void { out.put_string(self); }
    pub static def send_decode(input: SendReader) -> String { input.string() }
}
pub extension<T> Vec<T>: Sendable {
    pub def send_encode(out: SendWriter) -> Void where T: Sendable {
        out.enter();
        out.put_int(self.len());
        for index in 0..<(self.len() as i32) { self[index].send_encode(out); }
        out.leave();
    }
    pub static def send_decode(input: SendReader) -> Vec<T> where T: Sendable {
        let count = input.int();
        let out = Vec<T>.with_capacity(count as i32);
        for index in 0..<(count as i32) { out.push(T.send_decode(input)); }
        out
    }
}
pub extension<K, V> Dict<K, V>: Sendable {
    pub def send_encode(out: SendWriter) -> Void where K: Sendable, V: Sendable {
        out.enter();
        out.put_int(self.len());
        for entry in self.entries() { entry.key.send_encode(out); entry.value.send_encode(out); }
        out.leave();
    }
    pub static def send_decode(input: SendReader) -> Dict<K, V> where K: Sendable, V: Sendable {
        let count = input.int();
        let out = Dict<K, V>.new();
        for index in 0..<(count as i32) {
            let key = K.send_decode(input);
            out[key] = V.send_decode(input);
        }
        out
    }
}
pub extension<T> T?: Sendable {
    pub def send_encode(out: SendWriter) -> Void where T: Sendable {
        if let value = self { out.put_bool(true); value.send_encode(out); } else { out.put_bool(false); }
    }
    pub static def send_decode(input: SendReader) -> T? where T: Sendable {
        if !input.bool() { let none: T? = nil; return none; }
        let some: T? = T.send_decode(input);
        some
    }
}
pub extension<T, E> Result<T, E>: Sendable {
    pub def send_encode(out: SendWriter) -> Void where T: Sendable, E: Sendable {
        switch self {
            case .ok(let value): out.put_bool(true); value.send_encode(out);
            case .err(let error): out.put_bool(false); error.send_encode(out);
        }
    }
    pub static def send_decode(input: SendReader) -> Result<T, E> where T: Sendable, E: Sendable {
        if input.bool() { return Result<T, E>.ok(value: T.send_decode(input)); }
        Result<T, E>.err(error: E.send_decode(input))
    }
}
