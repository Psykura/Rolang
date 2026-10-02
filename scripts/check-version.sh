#!/bin/sh
# Requires the release version (e.g. from a v0.4.0 tag) to match the sources.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:?usage: check-version.sh VERSION}
status=0
grep -q "cli.version = \"rolangc $VERSION\";" "$ROOT/compiler/command.rl" || { echo "compiler/command.rl does not report rolangc $VERSION" >&2; status=1; }
grep -q "^VERSION ?= $VERSION\$" "$ROOT/Makefile" || { echo "Makefile VERSION is not $VERSION" >&2; status=1; }
exit $status
