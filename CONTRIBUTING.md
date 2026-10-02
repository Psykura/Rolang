# Contributing to Rolang

Fetch the pinned bootstrap compiler (BOOTSTRAP_VERSION) into genesis/, then
build with LLVM clang:

~~~sh
make bootstrap
make CLANG=/path/to/clang
~~~

Any released compiler can be used instead with
`make GENESIS=/path/to/rolang-VERSION-OS-ARCH/bin/rolangc`; see
[Genesis and releases](docs/genesis.md).

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

## Testing

Run `make test` for the suite in tests/ (conventions in
[tests/README.md](tests/README.md)) and `make check-selfhost` to require the
compiler to rebuild itself identically. Add a test for every fixed bug and
language change. CI runs the bootstrap, build, self-hosting check and tests for
every push to main and every pull request.

When the compiler sources start using a feature newer than BOOTSTRAP_VERSION,
release a version containing that feature first, then raise BOOTSTRAP_VERSION.

## Releases

Releases are built and published by GitHub Actions. Set the new version in
compiler/cli.rl (`rolangc X.Y.Z`) and the Makefile (`VERSION ?= X.Y.Z`), commit,
then push an annotated tag whose message becomes the release notes:

~~~sh
git tag -a vX.Y.Z -F notes.md
git push origin vX.Y.Z
~~~

The release workflow checks that the tag matches the sources, builds a
self-hosted compiler from the bootstrap, runs the tests and publishes the bundle
with SHA256SUMS.

## Compatibility

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
