# Genesis Compiler and releases

A Genesis Compiler is a platform-specific Rolang compiler executable supplied
with a release. It compiles the Rolang source in compiler/ to produce bin/rolangc.
The resulting compiler can compile subsequent versions of itself.

## Source builds

Download the matching Genesis Compiler binary and verify its SHA-256 against
the release's SHA256SUMS. The current sources use arrow closures and require a
Genesis Compiler from release 0.2.0 or later; 0.1.0 builds only the 0.1.0 and
0.2.0 sources. Make it executable, then build:

~~~sh
chmod +x /path/to/rolang-genesis
make GENESIS=/path/to/rolang-genesis CLANG=/path/to/clang
~~~

The default Genesis location is genesis/rolangc. This directory is local and
ignored by Git. The compiler receives explicit paths to this checkout's std/
and runtime/ and compiles compiler/main.rl once at O3. LLVM clang and a compatible
C compiler/linker are required to produce native programs.

Once built, bin/rolangc can compile the next source changes:

~~~sh
make rebuild GENESIS="$PWD/bin/rolangc" CLANG=/path/to/clang
~~~

The existing executable is replaced after compilation succeeds. Keep a released
Genesis Compiler outside bin/ for clean builds; make clean removes bin/ and
build/ while preserving genesis/.

## Preparing a release

The release producer supplies a Genesis Compiler executable that understands the
release sources and runtime ABI. Its initial generation happens outside this
source tree. Later releases can use a compatible released Rolang compiler.

Build and package on each supported host platform:

~~~sh
make rebuild GENESIS=/path/to/rolang-genesis CLANG=/path/to/clang
make release VERSION=0.2.0 GENESIS=/path/to/rolang-genesis
~~~

dist/VERSION/ contains:

- rolang-VERSION-OS-ARCH.tar.gz: the built compiler, std, runtime and license.
- rolang-genesis-VERSION-OS-ARCH: the supplied Genesis Compiler executable.
- SHA256SUMS: checksums for both assets.

Publish these files together. A Genesis binary belongs to its OS/architecture;
prepare a separate binary and bundle for each host. Packaging uses the host OS
and architecture, so provide a compiler built for that host.

The compiler bundle has bin/rolangc and lib/rolang/{std,runtime}. Extract it and
add its bin/ directory to PATH, or use make install PREFIX=/installation/path
from a source checkout. The resources include all .rl, .c and .h files; move them
together with the compiler so the C link entry can find its companion modules.
