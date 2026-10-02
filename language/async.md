# Rolang async tasks and socket I/O

Rolang compiles async functions to state machines. A single-threaded cooperative
scheduler runs ready tasks and uses POSIX `poll` for socket readiness and a
monotonic clock for timers. Pending operations let other tasks run; an idle
scheduler blocks instead of spinning.

## Async functions

```rolang
def load() async -> i32 { return 42; }

def main() async -> i32 {
    return await load();
}
```

`await` is available inside async functions. An ordinary async call waits for its
child task. Use `spawn` to start independent work before waiting for its result.

## Spawn and await

```rolang
import std.task
import std.io

def work(n: i32) async -> i32 {
    await sleep(10);
    return n * 2;
}

def main() async -> i32 {
    let first = spawn work(20);   // Task<i32>
    let second = spawn work(21);
    let a = await first;
    let b = await second;
    println(f"{a} {b}");
    return 0;
}
```

Arguments are evaluated when spawning, and the task retains heap arguments until
its frame is released. `spawn` returns immediately; the function body runs when
the scheduler next gets control. Named async functions, generic specializations,
statically resolved methods, async function values and async closures
(`(x: i32) async -> i32 { ... }`) can be spawned; awaiting a call through an
async function value starts and awaits its task. Dynamic protocol dispatch of
async requirements and spawning external C functions directly are not supported.

`Task<T>` has reference semantics: copying a binding aliases the same task.
`await task` returns a value of type `T`, including `Void`. A completed result can
be awaited repeatedly. Heap results retain their usual reference semantics.

## Task control

| Operation | Meaning |
| --- | --- |
| `task.done()` | Whether the task completed or was cancelled. |
| `task.cancel()` | Cancel unfinished work; return true only for the first successful cancellation. |
| `task.cancelled()` | Whether cancellation ended the task. |
| `await task.wait()` | Wait without extracting a result; return false for cancellation, true for normal completion. |
| `task.wait_blocking()` | Drive the scheduler from synchronous code until the task finishes; return the same completion status. |
| `await task` | Obtain the result; panics if the task was cancelled. |
| `await sleep(milliseconds)` | Suspend on a timer. Zero and negative durations yield without a delay. |
| `await yield_now()` | Give other ready tasks a chance to run. |

`spawn` is allowed in synchronous code. `wait_blocking()` provides a synchronous
bridge; prefer `await` inside async code so waits become state-machine suspension
points. Self-await and cyclic task dependencies panic with a diagnostic.

Dropping the last reference to a Task cancels unfinished work. A task retains its
result until its last reference is dropped. Cycles involving tasks are traced by
the cycle collector and may be reclaimed later.

Cancellation takes effect between resume steps. It cancels an implicit child
being awaited, releases the suspended frame and its managed resources, and wakes
waiters. It does not preempt running code. Cancelling a waiter does not cancel a
separately owned task that another caller may still await.

**Cancellation discards the suspended continuation, including pending `defer`
blocks.** Put resources that must be released on cancellation in managed objects
with `__release__` hooks. Code already running continues until it yields or
returns; side effects already performed are not rolled back.

Returning from `main` cancels remaining tasks and releases their frames. Keep
handles and await the work whose completion is required before exit.

## Asynchronous socket streams

Import `std.async_io` for `AsyncStream`, `AsyncListener`, and `AsyncPipe`. Import `std.task`
explicitly when using its timer/task APIs.

`AsyncPipe.create()` returns an optional pair of connected, full-duplex local
socket streams. This example writes from one task while another reads:

```rolang
import std.async_io
import std.task
import std.io

def writer(stream: AsyncStream) async -> i32 {
    await sleep(10);
    let written = await stream.write("hello");
    stream.shutdown_write();
    switch written {
        case .ok(let count): return count;
        case .err(let error): return -error;
    }
}

def main() async -> i32 {
    if let pair = AsyncPipe.create() {
        let sender = spawn writer(pair.second);
        while true {
            let result = await pair.first.read(4096);
            switch result {
                case .ok(let chunk):
                    if chunk.len() == 0 { break; }
                    print(chunk);
                case .err(let error): return error;
            }
        }
        let count = await sender;
        return 0;
    }
    return 1;
}
```

- `read(limit)` returns `Result<String, i32>`. Success contains at most `limit`
  bytes; an empty string means EOF, or a zero-length read. A negative limit
  returns an error. Read boundaries are byte boundaries and can split UTF-8.
- `write(value)` returns `Result<i32, i32>` after sending every byte, handling
  partial writes and backpressure. Success contains the byte count.
- Error values are positive POSIX `errno` numbers. A failed or cancelled write
  may already have sent a prefix; it is not transactional.
- `shutdown_write()` sends EOF after pending data has been written. Call it after
  awaiting writes. It returns zero on success or negative `errno` on failure.
- Concurrent reads can divide incoming bytes between readers; concurrent writes
  can interleave. Use one reader and one writer per stream when ordering matters.
- Pending operations retain the stream. Its descriptor closes after both its
  managed wrapper and all pending operations release their references.

### TCP connections and listeners

`await AsyncStream.connect("127.0.0.1", 8080)` returns
`Result<AsyncStream, i32>`. Connection setup suspends on socket readiness.
`AsyncListener.bind("127.0.0.1", 8080, 128)` returns
`Result<AsyncListener, i32>`; the third argument is a positive listen backlog.
Binding is immediate. `await listener.accept()` suspends and returns a connected
stream with the same read/write APIs. Both operations report positive POSIX errno
values on failure.

Use port `0` to request an available port and `listener.port()` to read it.
IPv6 numeric addresses such as `"::1"` are also supported. Hostnames and IPv6
scope identifiers are not resolved. Binding `"0.0.0.0"` or `"::"` exposes the
listener on wildcard interfaces; loopback addresses keep it local.

Connect and accept can be spawned and cancelled using `Task`. Pending accepts
retain their listener. Completed connections remain owned by their result;
dropping an unclaimed result closes the connection. No built-in timeout is
applied. See [the TCP example](../examples/async_tcp.rl).

For a connected socket obtained through FFI, `unsafe { AsyncStream.adopt(fd) }`
transfers exclusive descriptor ownership, including on failure, and makes the
socket nonblocking. The caller must stop using or closing that descriptor.
`Task.from_handle` and `raw_handle` are unsafe runtime integration APIs; a handle
must have the matching result representation and exactly one transferred owner.

## Implementation and limits

Each async function has an entry function, a resume function, and a heap frame.
Await points save locals and register a task dependency. The scheduler resumes
the frame only when the dependency completes. Results are copied from shared
Task handles or transferred from private child handles, with ARC ownership
preserved in both cases.

- Execution is cooperative, on one thread. CPU loops need explicit yields.
- Timer/socket I/O is implemented for POSIX hosts (Linux/macOS); validation here
  has been performed on Apple Silicon macOS.
- Existing `std.fs` and console I/O remain blocking. Regular-file asynchronous
  I/O, DNS, and TLS are not implemented. TCP requires numeric IPv4/IPv6 addresses.
- `poll` scans pending operations; this is not an epoll/kqueue scalability claim.
- Cancellation does not unwind suspended `defer` blocks, and cycle collection
  remains synchronous.
