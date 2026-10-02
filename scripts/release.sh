#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
VERSION=${VERSION:?Set VERSION, e.g. make release}
case "$VERSION" in
    ''|*[!A-Za-z0-9._-]*) echo "VERSION must contain letters, digits, dots, underscores or hyphens" >&2; exit 2 ;;
esac
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

This bin/rolangc also bootstraps the compiler sources: from a source checkout,
run make GENESIS=/path/to/this/bundle/bin/rolangc.

Rolang is licensed under MIT; see LICENSE.
EOF
tar -czf "$DIST/$NAME.tar.gz" -C "$WORK" "$NAME"
cd "$DIST"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$NAME.tar.gz" > SHA256SUMS
else
    shasum -a 256 "$NAME.tar.gz" > SHA256SUMS
fi
echo "Release assets: $DIST"
