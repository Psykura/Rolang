# C runtime and standard-library primitives

The C layer has two responsibilities: language execution services in runtime/
and standard-library primitives beside their Rolang APIs in std/.

| Core file | Responsibility |
| --- | --- |
| memory.c | Allocation pools, typed objects, ARC, module descriptors and cycle GC |
| panic.c | Fatal checks emitted by the compiler |
| scheduler.c | Task queues, suspension, deadlines, readiness polling and result ownership |
| entry.c | Program entry, arguments and scheduler shutdown |
| abi.h | Object headers, field/type descriptors and ownership hooks |
| task.h | Shared scheduler/task/stream state |
| api.h | Core C service declarations |
| platform.h | Platform and system-library includes |

The std modules with C implementations are string, vec, dict, char, io, fs, path,
process, panic, sha256, string_builder, task and async_io. Each keeps its .c
and .h beside the .rl API. Collections share the small-copy helper in
std/collections.h. String, vector and task layouts are shared through headers.
Pure Rolang modules reuse these APIs and do not need an empty C companion.

rolang_rt.c is a small composition entry containing includes. The compiler builds
it into one C object so C inlining and full/ThinLTO continue to see all modules.
Each implementation also compiles independently using its declared header
interfaces; a separate-object build omits the composition entry and links the
core and std objects together.

Language-visible rt_* symbols retain their ABI. Internal cross-module helpers
use the rl_* prefix and hidden visibility. Keep compiler-emitted layouts and
fast paths synchronized with abi.h and the std headers. Installations and release
bundles carry both directories, including all C sources and headers.
