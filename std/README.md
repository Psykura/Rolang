# Rolang standard library

The bundled std provides the foundations used by the compiler and applications.
Vec, Dict, String and the range foundation are implicit imports in ordinary
source files. Other modules use explicit imports such as `import std.io`.

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
| [vec](vec.rl) | Vec<T>, owned elements, indexed access and vector iteration |
| [dict](dict.rl) | Ordered Dict<K,V>, optional lookup/removal and snapshots |
| [string](string.rl) | String operations, conversions and literals; byte-oriented, with Unicode scalar and grapheme views |
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
| [cli](cli.rl) | Command-line parsing: flags, options with values/choices, positionals, help and suggestions |
| [task](task.rl) | Task ownership, cancellation, waits, sleep and yield |
| [async_io](async_io.rl) | Async socket streams, pipes, TCP connections and listeners |
| [math](math.rl) | Mathematical functions and numeric extension methods |
| [sha256](sha256.rl) | Binary-safe string/file SHA-256 |
| [panic](panic.rl) | Fatal panic/unreachable helpers |
| [test](test.rl) | Assertion helpers returning status values |

## Semantics worth preserving

String length/indexing/slicing count bytes; char helpers classify ASCII. String
literals can contain UTF-8 and NUL, but these APIs do not imply Unicode scalar
or grapheme indexing. ByteString and text APIs will be given clearer distinct
contracts as the library evolves.

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
    cli.flag("loud", "print in capitals").short("l");
    cli.option("times", "N", "repeat N times").short("n");
    cli.positional("NAME", "who to greet");
    guard let args = cli.parse_process() else { return cli.status; }
    let times = (args.value("times") ?? "1").to_i32();
    0
}
~~~

Options accept `--name value`, `--name=value`, `-n value` and `-nvalue`; short
flags combine and `--` ends options. Repeating an option is allowed: `value`
returns the last occurrence, `values` all of them in order. `choices` restricts
values, `implicit` makes a value optional (`--lto` or `--lto=thin`), `preset`
adds spellings that set a fixed value (`--no-lto`), and `exclusive` rejects
combinations. `--help` output is generated from the declarations. Errors such
as an unknown option (with a closest-spelling suggestion) print to stderr and
leave `status` 2; `parse` returns them as a Result instead.

## Library development

The next work is explicit errors, typed handles, ownership/mutability guarantees,
byte/UTF-8 separation, common collection interfaces and platform contracts.
JSON/TOML, time, randomness, richer networking and serialization are planned.
Document new contracts, including edge, failure and ownership behavior.
See [the roadmap](../docs/roadmap.md) and [language semantics](../language/README.md).
