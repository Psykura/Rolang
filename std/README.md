# Rolang standard library

The bundled std provides the foundations used by the compiler and applications.
Vec, Dict, String, compare and the range foundation are implicit imports in
ordinary source files. Other modules use explicit imports such as `import std.io`.

Modules with platform or storage primitives have a matching .c implementation
and .h interface beside their .rl API: string, vec, dict, char, io, fs, path,
process, panic, sha256, string_builder, task and async_io. String's Unicode views
use unicode.c with unicode_tables.h, generated from the Unicode Character
Database by scripts/gen-unicode-tables.py. Other modules use Rolang
implementations, shared std operations or system math functions.
The [runtime core](../runtime/README.md) provides allocation, ARC/GC and scheduling.

## Modules

| Module | Current responsibilities |
| --- | --- |
| [vec](vec.rl) | Vec<T>, owned elements, indexed access, iteration, stable sort_by, binary search and reversal |
| [dict](dict.rl) | Ordered Dict<K,V>, optional lookup/removal and snapshots |
| [string](string.rl) | String operations, conversions and literals; byte-oriented, with Unicode scalar and grapheme views |
| [compare](compare.rl) | Equatable, Comparable and Hashable; Vec sort, min, max, binary_search, contains, index_of, ==, hash; hash_combine |
| [range](range.rl) | Half-open/inclusive language range support |
| [cell](cell.rl) | Compiler support: shared storage for variables captured and reassigned by closures |
| [array](array.rl) | Numeric Vec<i32> helpers: sum, product, search and extrema |
| [set](set.rl) | Set<T>, membership, removal and snapshots |
| [linked_list](linked_list.rl) | Generic linked-list storage and operations |
| [hash_map](hash_map.rl) | Structural-key maps with supplied hash/equality callbacks |
| [collections](collections.rl) | Vector transforms, folds, search, slicing and string joining |
| [iter](iter.rl) | Byte-character and lazy dictionary-key iteration |
| [iterator](iterator.rl) | Lazy Iter<T>, map/filter/take/zip/enumerate/collect/fold |
| [option](option.rl) | Combinators on the language's T? type |
| [result](result.rl) | Result<T,E>, map/map_err/and_then and fallback operations |
| [bytestring](bytestring.rl) | Mutable byte-string helpers |
| [char](char.rl) | ASCII byte classification and case conversion |
| [string_builder](string_builder.rl) | Reusable buffer and independent text snapshots |
| [code_writer](code_writer.rl) | Indented generated source and C byte escaping |
| [interner](interner.rl) | Stable string IDs scoped to an interner |
| [io](io.rl) | Console and standard-stream I/O and terminal detection |
| [fs](fs.rl) | File handles, checked reads, atomic writes/copies and filesystem operations |
| [path](path.rl) | Path operations and directory listing |
| [process](process.rl) | Arguments, environment, executable identity and argv-based processes |
| [time](time.rl) | Duration, monotonic Instant, DateTime (RFC 3339, strftime-style format, local offset) and sleeping |
| [random](random.rl) | Seedable xoshiro256** generator: ranges, floats, choice, shuffle, sampling; OS entropy |
| [json](json.rl) | Json values, RFC 8259 parsing with positions, compact/pretty output; Codable, encode_json/decode_json |
| [toml](toml.rl) | TOML 1.0 documents to and from Json values; passes the toml-test suite |
| [cli](cli.rl) | Command-line parsing: flags, options with values/choices, positionals, help and suggestions |
| [task](task.rl) | Task ownership, cancellation, waits, sleep and yield |
| [async_io](async_io.rl) | Async TCP streams and listeners (host names resolved), UDP sockets, pipes, DNS resolution, errno messages |
| [http](http.rl) | HTTP/1.1 client (redirects, timeouts, chunked bodies) and server (a task per connection, keep-alive); URLs and query strings |
| [math](math.rl) | Mathematical functions and numeric extension methods |
| [sha256](sha256.rl) | Binary-safe string/file SHA-256 |
| [panic](panic.rl) | Fatal panic/unreachable helpers |
| [test](test.rl) | Assertion helpers returning status values |

## Semantics worth preserving

String length/indexing/slicing count bytes; char helpers classify ASCII. String
literals can contain UTF-8 and NUL, but these APIs do not imply Unicode scalar
or grapheme indexing. ByteString and text APIs will be given clearer distinct
contracts as the library evolves.

Dict keys and Set elements of struct or payload-enum types compare by content
when the type is Hashable, defining `hash() -> u64` and `__eq__` (equal values
must hash alike; `hash_combine` mixes field hashes). Without them such keys
compare by identity. Numbers, Bool, String and Vec of Hashable elements are
Hashable, as are optionals of Hashable types.

Collections own their managed elements. Assignment shares the container.
Snapshots copy bindings while retaining referenced objects; they are shallow.
Avoid structural mutation during live iteration. HashMap key equality/hashing
must remain stable while keys are stored.

Filesystem/process APIs currently expose POSIX conventions and some sentinel
results. Checked reads distinguish empty content from failure. Async socket
APIs return Result values with errno errors; console/filesystem I/O remains
blocking. Some wrappers require explicit handle closure; automatic-memory
management alone does not make every API a resource-owning abstraction.

## Command-line parsing

std.cli declares a program's options and parses the process arguments:

~~~rolang
import std.cli

def main() -> i32 {
    let cli = CommandLine.new("greet", "[options] NAME");
    cli.flag("loud", "print in capitals", short: "l");
    cli.option("times", "N", "repeat N times", short: "n");
    cli.positional("NAME", "who to greet");
    guard let args = cli.parse_process() else { return cli.status; }
    let times = (args.value("times") ?? "1").to_i32();
    0
}
~~~

Options accept `--name value`, `--name=value`, `-n value` and `-nvalue`; short
flags combine and `--` ends options. Repeating an option is allowed: `value`
returns the last occurrence, `values` all of them in order. Labeled parameters
configure an option: `choices` restricts values, `implicit` makes a value
optional (`--lto` or `--lto=thin`), `hidden` leaves it out of help. `preset`
adds spellings that set a fixed value (`--no-lto`), and `exclusive` rejects
combinations. `--help` output is generated from the declarations. Errors such
as an unknown option (with a closest-spelling suggestion) print to stderr and
leave `status` 2; `parse` returns them as a Result instead.

## Time, randomness and JSON

Duration spans are signed nanoseconds and print in the largest fitting unit
(`1.5s`, `250ms`). Instant reads the monotonic clock; DateTime is a Gregorian
date and time at a fixed UTC offset, parsed from and printed as RFC 3339, with
`format("%Y-%m-%d")` patterns. Leap seconds are not represented.
`sleep_blocking` stops the thread; async code uses `sleep_for`.

Random is xoshiro256**: fast and reproducible with `Random.seeded(n)`, but not
cryptographic; `entropy_u64()` reads the operating system's entropy source.
Integer ranges are half-open and unbiased.

Json keeps integers that fit in i64 exact and other numbers as f64. Objects
keep key order. `json["a"]["b"]` yields null for missing members; `get`/`at`
return optionals. Parse errors carry a line and column. Output escapes control
characters and writes NaN or infinity as null.

### Codable

`struct User: Codable { ... }` derives `to_json()` and `static from_json(value)`.
`encode_json(value)` gives text and `let user: Result<User, DecodeError> =
decode_json(text)` reads it back; `decode_toml`/`encode_toml` do the same for
TOML. Numbers, Bool, String, Json, Vec and Dict (String or integer keys) are
Codable; integers are range-checked. Optional fields decode a missing member
or null as nil, fields with a default use it when missing, and errors name the
path: `roles[0].member: expected an integer, found a string`. Enum cases
without payload encode as their name, others as `{"case": payload}`.

`Toml.parse` reads TOML 1.0 into the same Json values: tables are objects in
document order, dates and times stay RFC 3339 strings. `Toml.encode` writes an
object back, with nested objects as `[tables]` and arrays of objects as
`[[tables]]`; TOML has no null, so encoding one is an error. The parser passes
all 208 valid and rejects all 501 invalid documents of the toml-test 1.0 suite.

## Networking

`await resolve(host)` returns numeric addresses, IPv4 first. The system
resolver runs on a helper thread, so other tasks continue meanwhile.
`AsyncStream.connect(host, port)` resolves names and tries each address.
`UdpSocket` sends and receives datagrams with their sender. Errors are errno
values; `os_error_message(code)` gives the system's text.

std.http speaks HTTP/1.1 over these streams. `http_get`/`http_post` and
`HttpClient` (timeout, redirects, default headers) return `HttpResponse` or an
`HttpError` with a message. `HttpServer.serve(handler)` runs an async handler
for every request, each connection in its own task, with keep-alive. Bodies
are binary-safe strings framed by Content-Length or chunked encoding; headers
are limited to 64 KiB and bodies to a configurable size. A server closes connections whose request does not
arrive within `idle_timeout` (60 seconds). https needs TLS,
which is not available yet. `with_timeout(task, duration)` in std.time bounds
any task.

## Library development

The next work is explicit errors, typed handles, ownership/mutability guarantees,
byte/UTF-8 separation, common collection interfaces and platform contracts.
TLS is planned.
Document new contracts, including edge, failure and ownership behavior.
See [the roadmap](../docs/roadmap.md) and [language semantics](../language/README.md).
