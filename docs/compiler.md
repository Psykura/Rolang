# Rolang compiler and artifacts

`rolangc` compiles one entry source and its import graph. The default level is O2.
O0/O1/O2/O3 select mandatory lowering plus the corresponding optimization passes.

~~~sh
rolangc program.rl -o program
rolangc -c program.rl -o program.o
rolangc --emit llvm program.rl -o program.ll
rolangc --emit llvm-opt -O3 program.rl -o program.opt.ll
rolangc --emit asm program.rl -o program.s
rolangc --emit mir program.rl
rolangc --emit mir-opt -O3 program.rl
rolangc -I dependencies program.rl
~~~

Text outputs use stdout unless -o is supplied. Objects/modules/executables use
source-derived output names when -o is omitted. Existing output is preserved
when compilation fails. Output cannot overwrite an input or imported artifact.

## Resources and tools

Repository binaries find std/ and runtime/ relative to the executable's parent.
Installed binaries find PREFIX/lib/rolang/{std,runtime}.

runtime/rolang_rt.c is the C link entry. It includes the runtime core and each
std module's C companion, with shared layouts defined in headers. Preserve both
directories when relocating or installing resources. Runtime dependency scanning
includes companion C sources and headers in content-cache validation.

Resource/tool overrides:

| Option/environment | Meaning |
| --- | --- |
| --stdlib / ROLANG_STDLIB | Root containing std/ |
| --runtime / ROLANG_RUNTIME | C runtime file |
| --clang / ROLANG_CLANG | LLVM toolchain |
| --cc / CC | Runtime compiler and linker driver |
| --linker | Linker selected through clang |
| --target | Supported 64-bit target triple |

Tool commands must name executable files; argument vectors preserve spaces and
other path characters. A target triple alone does not supply a sysroot, target
libraries or execution validation. The implemented ABI is 64-bit POSIX.

## Diagnostics

Errors and warnings go to stderr as `error: message`, followed by
` --> file:line:column`, the source line and a caret underline of the span.
Paths are shown relative to the working directory. Output is colored when
stderr is a terminal, NO_COLOR is unset and TERM is not `dumb`;
`--color=always|never` (or `--no-color`) overrides this. A summary such as
`2 errors generated.` ends the output; the exit status is 1.

The parser recovers at statement and declaration boundaries, so a run reports
every syntax error in the file. Name resolution errors do not stop type
checking; type errors caused by an earlier error (an operand of error type) are
suppressed. Diagnostics are ordered by file, then position.

Command-line errors print `rolangc: message` with a `--help` hint and exit
with status 2; unknown options suggest the closest spelling.

## Panics and backtraces

A runtime panic prints `rolang panic: message` and aborts. With
`ROLANG_BACKTRACE=1` it also prints the call stack, innermost first; inlined
functions do not appear as frames, so -O0 shows the most detail. Generated
functions keep frame pointers for this purpose.

## Inspection

Use `--inspect PASS` with --stdlib ROOT, where PASS is parse, resolve, check,
hir, mono, mir, mir-post or llvm; `--check` is short for `--inspect check`.
--fields with --mir/--mir-post emits the precise MIR field protocol. Normal
--emit mir/--emit mir-opt produce readable MIR.

## Compiled libraries

~~~sh
rolangc --emit module library.rl -o library.rlm
rolangc consumer.rl -o consumer
~~~

The consumer imports `"library.rlm"`. Libraries export pub declarations and
cannot define main. Build dependencies as .rlm artifacts before exporting a
dependent library. Source/generic metadata and transitive objects are retained,
so relocated libraries can work after their original sources are removed.

The format uses bounded, byte-length-prefixed records and SHA-256 validation:
`rolang-module-1` with `rolang-abi-1`. Target, ABI, source identity, object checksum
and dependency conflicts are checked. Rebuild dependencies when compiler
module or runtime ABI versions change.

## LTO

--lto/--lto=full and --lto=thin are opt-in. --no-lto disables it. The LLVM and
C toolchains/linker must understand compatible bitcode. -c --lto emits bitcode;
--emit module --lto can distribute bitcode in .rlm. Non-LTO consumers compile
imported bitcode before linking. Native objects may also participate in links.

## Content cache

--cache-dir enables caching for executable/object/module outputs; --no-cache
disables it. -v prints real compilation/cache-hit diagnostics. Keys include
compiler/tools, source/import inputs, runtime/header dependencies, relevant
environment, output/options, LTO and linker information. Corrupt or unusable cache
data triggers recompilation rather than compiler fallback.
Current records use `rolang-cache-1`. No cache is needed for correctness.
