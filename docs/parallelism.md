# Parallel functions

Rolang runs async code on a cooperative scheduler per thread. `parallel def`
functions run on a pool of worker threads, each with its own scheduler, so
CPU-bound work uses every core while ordinary code keeps its single-threaded
semantics and costs.

```rolang
struct Tile: Sendable { let pixels: Vec<u8>; let width: i32; }

parallel def blur(tile: Tile) async -> Tile { ... }

def main() async -> i32 {
    let tiles = load_tiles();
    let jobs = Vec<Task<Tile>>.new();
    for tile in tiles { jobs.push(spawn blur(tile)); }   // run in parallel
    for job in jobs { save(await job); }
    0
}
```

## Model

- **Threads share no objects.** Each worker thread has its own scheduler,
  cycle collector and allocation pools. Reference counts stay non-atomic, so
  programs that never call a parallel function pay nothing.
- **Values cross threads by copy.** A parallel function's parameters and
  result must be `Sendable`. The caller encodes the arguments into a buffer
  owned by no thread; the worker decodes them into its own objects, and the
  result travels back the same way. Mutating an argument inside a parallel
  function does not affect the caller's value.
- **Call sites are unchanged.** `await f(x)` waits for the result; `spawn
  f(x)` starts it and returns a `Task`. The declaration decides where the
  function runs.
- **Workers run full async code.** A parallel function may await, spawn
  local tasks, sleep, do file and network I/O, and call other parallel
  functions, all on its worker thread.

## Sendable

`Sendable` (std.parallel) has two requirements, `send_encode(out: SendWriter)`
and `static send_decode(input: SendReader) -> Self`. Integers, floats, Bool,
String, Vec, Dict, optionals and Result of Sendable values conform. A struct or
enum declaring `: Sendable` derives both methods from its fields or cases,
which must be Sendable themselves; types holding resources (sockets, files,
tasks) or functions cannot be sent. Encoding is depth-limited, so a cyclic
value fails instead of encoding forever.

## Rules

- A parallel function is a top-level `async` function; it cannot be generic
  or a method.
- A file using `parallel def` or `: Sendable` imports std.parallel implicitly.
- `ROLANG_WORKERS` sets the number of workers; the default is one per
  processor. Workers start on the first parallel call.
- Jobs go to the least busy worker and stay there; a job does not move
  between threads once started.
- A panic on a worker ends the process, as on the main thread.

## Implementation

- `parallel def name` is expanded by the parser: the body becomes
  `__parallel_body_name`; `name` encodes the arguments and awaits
  `__parallel_call`, which queues a job; on the worker,
  `__parallel_start_name` starts `__parallel_run_name` as a detached task,
  which decodes the arguments, awaits the body and encodes the result.
- The runtime (std/parallel.c) keeps a queue per worker. A finished job goes
  to the calling thread's inbox, and a byte on that thread's wake pipe makes
  its scheduler complete the waiting task. A waiting task holds no file
  descriptor, so thousands of outstanding jobs cost nothing to poll.
- With `ROLANG_THREADED` (set by the compiler driver) the runtime's
  scheduler, collector and pools are thread-local. The allocation fast path
  that generated code inlines reads them through one thread-local struct
  (`rl_hot`), one thread-local address per allocation. A runtime built by an
  older compiler (the bootstrap) keeps process-wide state and refuses
  parallel calls.
- The scheduler keeps runnable tasks on a ready queue, waiting tasks on the
  waiters list of the task they await, native tasks on their own list and
  finished tasks on a retire queue, so a step costs time in its own work
  rather than in the number of tasks alive.
