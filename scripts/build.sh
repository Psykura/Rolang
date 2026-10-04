#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
GENESIS=${GENESIS:-"$ROOT/genesis/rolangc"}
CLANG=${CLANG:-clang}
CC=${CC:-"$CLANG"}
GENESIS=$(command -v "$GENESIS") || {
    echo "Set GENESIS to a Genesis Compiler executable from a Rolang release" >&2
    exit 1
}
test -x "$GENESIS" || { echo "GENESIS must be executable" >&2; exit 1; }
CLANG=$(command -v "$CLANG") || { echo "LLVM clang is required" >&2; exit 1; }
CC=$(command -v "$CC") || { echo "C compiler is required" >&2; exit 1; }
mkdir -p "$ROOT/build" "$ROOT/bin"
OUTPUT="$ROOT/build/rolangc.$$"
trap 'rm -f "$OUTPUT" "$ROOT/bin/rolangc.new"' EXIT HUP INT TERM
echo "Building Rolang with Genesis Compiler"
# One LLVM module: the released compiler keeps cross-module inlining
# (a compiler split for parallel compilation runs about 4% slower).
ROLANG_JOBS=1 "$GENESIS" --stdlib "$ROOT" --runtime "$ROOT/runtime/rolang_rt.c" \
    --clang "$CLANG" --cc "$CC" -O3 "$ROOT/compiler/main.rl" -o "$OUTPUT"
cp "$OUTPUT" "$ROOT/bin/rolangc.new"
chmod 755 "$ROOT/bin/rolangc.new"
mv "$ROOT/bin/rolangc.new" "$ROOT/bin/rolangc"
echo "Ready: $ROOT/bin/rolangc"
