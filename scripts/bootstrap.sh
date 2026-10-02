#!/bin/sh
# Downloads the release bundle named by BOOTSTRAP_VERSION for this host, verifies
# its checksum and installs its compiler as genesis/rolangc (the default GENESIS).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${BOOTSTRAP_VERSION:-$(cat "$ROOT/BOOTSTRAP_VERSION")}
RELEASES=${ROLANG_RELEASES:-https://github.com/Psykura/Rolang/releases/download}
case $(uname -s) in Darwin) OS=darwin ;; Linux) OS=linux ;; *) echo "Unsupported host" >&2; exit 1 ;; esac
case $(uname -m) in arm64|aarch64) ARCH=arm64 ;; x86_64|amd64) ARCH=x86_64 ;; *) echo "Unsupported architecture" >&2; exit 1 ;; esac
NAME="rolang-$VERSION-$OS-$ARCH"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
curl -fsSL -o "$WORK/$NAME.tar.gz" "$RELEASES/v$VERSION/$NAME.tar.gz" || { echo "No $NAME bundle in release v$VERSION" >&2; exit 1; }
curl -fsSL -o "$WORK/SHA256SUMS" "$RELEASES/v$VERSION/SHA256SUMS"
grep " $NAME.tar.gz\$" "$WORK/SHA256SUMS" > "$WORK/expected"
if command -v sha256sum >/dev/null 2>&1; then (cd "$WORK" && sha256sum -c expected >/dev/null)
else (cd "$WORK" && shasum -a 256 -c expected >/dev/null); fi
tar -xzf "$WORK/$NAME.tar.gz" -C "$WORK"
mkdir -p "$ROOT/genesis"
cp "$WORK/$NAME/bin/rolangc" "$ROOT/genesis/rolangc"
chmod 755 "$ROOT/genesis/rolangc"
echo "Bootstrap compiler: genesis/rolangc ($("$ROOT/genesis/rolangc" --version))"
