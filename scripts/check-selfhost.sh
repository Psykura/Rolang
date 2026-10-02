#!/bin/sh
# Builds the compiler with itself twice and requires identical binaries, starting
# from bin/rolangc. Leaves the self-built compiler in bin/rolangc.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
test -x bin/rolangc || { echo "Run make first" >&2; exit 1; }
mkdir -p build/selfhost
cp bin/rolangc build/selfhost/stage1
make rebuild GENESIS="$ROOT/build/selfhost/stage1" CLANG="${CLANG:-clang}"
cp bin/rolangc build/selfhost/stage2
make rebuild GENESIS="$ROOT/build/selfhost/stage2" CLANG="${CLANG:-clang}"
if cmp -s bin/rolangc build/selfhost/stage2; then
    echo "Self-hosting fixpoint: stage 2 and stage 3 compilers are identical"
else
    echo "Self-hosting fixpoint failed: stage 2 and stage 3 compilers differ" >&2
    exit 1
fi
