#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=${VERSION:-0.1.0}
case "$VERSION" in
    ''|*[!A-Za-z0-9._-]*) echo "VERSION must contain letters, digits, dots, underscores or hyphens" >&2; exit 2 ;;
esac
GENESIS=${GENESIS:-"$ROOT/genesis/rolangc"}
GENESIS=$(command -v "$GENESIS") || { echo "Set GENESIS to the release's Genesis Compiler executable" >&2; exit 1; }
test -x "$GENESIS" || { echo "GENESIS must be executable" >&2; exit 1; }
test -x "$ROOT/bin/rolangc" || { echo "Run make first" >&2; exit 1; }
case $(uname -s) in
    Darwin) OS=darwin ;;
    Linux) OS=linux ;;
    *) echo "Unsupported release host" >&2; exit 1 ;;
esac
case $(uname -m) in
    arm64|aarch64) ARCH=arm64 ;;
    x86_64|amd64) ARCH=x86_64 ;;
    *) echo "Unsupported release architecture" >&2; exit 1 ;;
esac
NAME="rolang-$VERSION-$OS-$ARCH"
SEED="rolang-genesis-$VERSION-$OS-$ARCH"
DIST="$ROOT/dist/$VERSION"
WORK=$(mktemp -d "$ROOT/build/release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
mkdir -p "$DIST" "$WORK/$NAME"
"$ROOT/scripts/install.sh" "$WORK/$NAME"
cp "$ROOT/LICENSE" "$WORK/$NAME/LICENSE"
cat > "$WORK/$NAME/README.md" <<'EOF'
# Rolang

This bundle contains bin/rolangc, lib/rolang/std and lib/rolang/runtime.
Keep these directories together and add bin/ to PATH.

LLVM clang and a compatible C compiler/linker are required to compile native
programs. Run rolangc program.rl -o program, then execute ./program.

The separate Genesis Compiler release asset compiles the Rolang compiler source.
From a source checkout, run make GENESIS=/path/to/rolang-genesis.

Rolang is licensed under MIT; see LICENSE.
EOF
tar -czf "$DIST/$NAME.tar.gz" -C "$WORK" "$NAME"
cp "$GENESIS" "$DIST/$SEED"
chmod 755 "$DIST/$SEED"
cd "$DIST"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$NAME.tar.gz" "$SEED" > SHA256SUMS
else
    shasum -a 256 "$NAME.tar.gz" "$SEED" > SHA256SUMS
fi
echo "Release assets: $DIST"
