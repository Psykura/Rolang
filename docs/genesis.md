# Genesis Compiler and releases

The Genesis Compiler is the initial Rolang compiler executable, produced outside
this source tree and published once, as the rolang-genesis asset of release
0.1.0. Every later release ships its compiler in the release bundle, and that
compiler builds the next sources, so no further genesis binaries are needed.

## Source builds

Building compiler/ needs an existing Rolang compiler for the host platform (the
GENESIS make variable). Use bin/rolangc from a release bundle: download the
matching rolang-VERSION-OS-ARCH.tar.gz, verify its SHA-256 against the release's
SHA256SUMS and extract it. The current sources require release 0.2.0 or later.

~~~sh
make GENESIS=/path/to/rolang-VERSION-OS-ARCH/bin/rolangc CLANG=/path/to/clang
~~~

The default location is genesis/rolangc. This directory is local and ignored by
Git. The compiler receives explicit paths to this checkout's std/ and runtime/
and compiles compiler/main.rl once at O3. LLVM clang and a compatible C
compiler/linker are required to produce native programs.

Once built, bin/rolangc can compile the next source changes:

~~~sh
make rebuild GENESIS="$PWD/bin/rolangc" CLANG=/path/to/clang
~~~

The existing executable is replaced after compilation succeeds. Keep a released
compiler outside bin/ for clean builds; make clean removes bin/ and build/ while
preserving genesis/.

## Preparing a release

Releases are produced by the GitHub Actions release workflow when a vX.Y.Z tag is
pushed (see [CONTRIBUTING](../CONTRIBUTING.md#releases)). It fetches the
BOOTSTRAP_VERSION compiler, builds the sources, rebuilds them with the result so
the shipped compiler is self-built and reproducible (`make check-selfhost`), runs
the tests and runs `make release VERSION=X.Y.Z`.

dist/VERSION/ contains:

- rolang-VERSION-OS-ARCH.tar.gz: the built compiler, std, runtime and license.
- SHA256SUMS: the bundle checksum.

A bundle belongs to its OS/architecture; package each host separately.

The compiler bundle has bin/rolangc and lib/rolang/{std,runtime}. Extract it and
add its bin/ directory to PATH, or use make install PREFIX=/installation/path
from a source checkout. The resources include all .rl, .c and .h files; move them
together with the compiler so the C link entry can find its companion modules.
