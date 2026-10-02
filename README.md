# Rolang

Rolang is a statically typed, compiled language with automatic memory management.
Its compiler is written in Rolang and emits LLVM IR for native executables.
The language combines shared reference semantics, ARC with a cycle collector,
generics, protocols, payload enums, pattern matching, closures and cooperative
async/await.

The full [language introduction](language/README.md) explains the syntax,
design philosophy, core features and distinctive runtime behavior.

## What is here

- One Rolang compiler: parser, resolution, type checking, HIR/MIR, specialization,
  async lowering, ownership passes, LLVM text backend and build driver.
- A C runtime core for ARC/GC, allocation, compiler checks and task scheduling.
- 29 std modules covering collections, text, I/O, paths, processes, math and tasks;
  modules with C primitives keep their implementations beside their Rolang API.
- A bootstrap build entry point and relocatable installation.

Project/workspace/package management and LSP are planned in the
[roadmap](docs/roadmap.md). The current public command is `rolangc`.

## Requirements and build

Use a 64-bit POSIX host, LLVM clang, a compatible C compiler/linker, make and a
bootstrap compiler executable for your host platform. The bootstrap compiler is a
released Rolang compiler binary used to compile the current Rolang sources; the
current sources require the 0.2.0 release or later.

`make bootstrap` downloads the release named in BOOTSTRAP_VERSION for your
platform, verifies it and installs its compiler as genesis/rolangc, which make
uses by default:

~~~sh
make bootstrap
make CLANG=/path/to/clang
~~~

Alternatively, pass any release bundle's compiler with
`make GENESIS=/path/to/rolang-VERSION-OS-ARCH/bin/rolangc`. The build
compiles compiler/main.rl and its imports once at O3, then installs the result
as bin/rolangc. CC defaults to CLANG; LTO needs a compatible linker.

## Quick start

~~~rolang
import std.io

def main() -> i32 {
    println("Hello, Rolang!");
    0
}
~~~

~~~sh
bin/rolangc examples/hello.rl -o build/hello
build/hello
make install PREFIX="$HOME/.local"
~~~

Installation places `rolangc` in `PREFIX/bin` and std/runtime resources in
`PREFIX/lib/rolang`. The whole installation can be relocated. Add `PREFIX/bin`
to PATH when using the installed command.

## Compiler commands

| Command | Output or purpose |
| --- | --- |
| `rolangc program.rl -o program` | Native executable; defaults to O2 |
| `rolangc -O3 program.rl` | Select O0, O1, O2 or O3 |
| `rolangc -c program.rl -o program.o` | Object file |
| `rolangc -g -O0 program.rl` | Debug build for lldb/gdb; a `program.dSYM` on macOS |
| `rolangc --emit llvm program.rl` | LLVM text |
| `rolangc --emit llvm-opt -O3 program.rl` | Backend-optimized LLVM |
| `rolangc --emit asm program.rl` | Assembly |
| `rolangc --emit mir program.rl` | MIR before async/ownership postprocessing |
| `rolangc --emit mir-opt program.rl` | Lowered MIR with ownership/optimization passes |
| `rolangc --emit module library.rl -o library.rlm` | Compiled library |
| `rolangc --lto=thin -O3 program.rl` | ThinLTO; --lto selects full LTO |
| `rolangc -I dependencies program.rl` | Add an import root |
| `rolangc --cache-dir build/cache program.rl` | Enable content cache |

Text modes write to stdout unless `-o FILE` is given.
`--clang`, `--cc` and `--linker` choose tools;
`--stdlib` and `--runtime` override resources. `--inspect PASS` (or `--check`,
`--mir`, …) prints a compiler pass; pass `--stdlib ROOT` to supply the std root
in these modes. `rolangc --help` lists every option.

Errors point at the source with a caret underline, and one run reports every
syntax error and the type errors that do not follow from earlier ones:

~~~text
error: Cannot assign String to i32 in variable initializer
 --> main.rl:2:18
  |
2 |     let a: i32 = "x";
  |                  ^^^
~~~

Diagnostics are colored on a terminal (`--color=always|never|auto`, NO_COLOR).
A panicking program prints its call stack when run with `ROLANG_BACKTRACE=1`.
See [compiler usage and artifacts](docs/compiler.md).

## Documentation

| Guide | Contents |
| --- | --- |
| [Language](language/README.md) | Philosophy, features, syntax, memory and async semantics |
| [Standard library](std/README.md) | All bundled modules and current API boundaries |
| [Compiler](docs/compiler.md) | CLI, imports, .rlm, cache, targets and LTO |
| [Architecture](compiler/README.md) | Compiler stages and runtime/ABI responsibilities |
| [Runtime](runtime/README.md) | C core, standard-library companions and shared ABI |
| [Contributing](CONTRIBUTING.md) | Source layout and development workflow |
| [Roadmap](docs/roadmap.md) | Standard library, management, distribution and editor work |

## Development

~~~sh
make rebuild GENESIS="$PWD/bin/rolangc" CLANG=/path/to/clang
make test
make check-selfhost
~~~

After the first build, the resulting compiler can compile subsequent source
changes. Keep a released bootstrap compiler available for a clean build.
`make test` runs the [test suite](tests/README.md) and `make check-selfhost`
requires the compiler to rebuild itself identically; CI runs both, and tagged
releases are published by GitHub Actions (see [CONTRIBUTING](CONTRIBUTING.md)).
The language uses reference semantics even when an optimization replaces an
allocation with scalars. Build and install instructions apply to each platform
with a matching bootstrap compiler and compatible toolchain.

Rolang is licensed under [MIT](LICENSE).
