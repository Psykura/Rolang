# Contributing to Rolang

Build with a Genesis Compiler and LLVM clang:

~~~sh
make GENESIS=/path/to/rolang-genesis CLANG=/path/to/clang
~~~

Compiler source lives in compiler/, std in std/, and the C runtime core in runtime/.
Keep C standard-library implementations in std/ beside the matching .rl API and
.h interface. Maintain shared layouts in runtime/abi.h and runtime/task.h.
Node definitions, visitors and dumps are checked-in Rolang source; maintain
related files together. Keep language semantics and API documentation aligned
with implementation changes.

After the first build, use the current compiler to build source changes:

~~~sh
make rebuild GENESIS="$PWD/bin/rolangc" CLANG=/path/to/clang
~~~

Version incompatible module/runtime contracts and update the
[artifact guide](docs/compiler.md). Release assets and the initial compiler
binary are described in [Genesis and releases](docs/genesis.md).

Runnable language examples live in examples/language/. Their source is reproduced
in [the language README](language/README.md). Keep examples and documentation
synchronized.

Use the public name Rolang, compiler command rolangc and std.* module paths.
Planned project/package commands should use a separate Rolang entry point and
reuse the compiler service API. Work through the [roadmap](docs/roadmap.md) in
buildable slices and document implemented and planned behavior accurately.
