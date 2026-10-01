#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if test "$#" -ne 1 || test -z "$1"; then
    echo "usage: $0 PREFIX" >&2; exit 2
fi
PREFIX=$1
test -x "$ROOT/bin/rolangc" || { echo "Run make first" >&2; exit 1; }
mkdir -p "$PREFIX/bin" "$PREFIX/lib/rolang/std" "$PREFIX/lib/rolang/runtime"
cp "$ROOT/bin/rolangc" "$PREFIX/bin/rolangc"
chmod 755 "$PREFIX/bin/rolangc"
cp "$ROOT"/std/*.rl "$ROOT"/std/*.c "$ROOT"/std/*.h "$PREFIX/lib/rolang/std/"
cp "$ROOT"/runtime/*.c "$ROOT"/runtime/*.h "$PREFIX/lib/rolang/runtime/"
echo "Installed compiler and resources under $PREFIX"
