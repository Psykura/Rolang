#!/bin/bash
# Runs the test suite with ROLANGC (default bin/rolangc), in parallel:
#   tests/run/**          programs that must compile and run as expected
#   tests/compile_fail/** programs that must be rejected with a given error
#   examples/             programs that must compile and exit 0
# A directory containing main.rl is one multi-file case. An optional filter
# argument keeps only cases whose path contains it.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RC=${ROLANGC:-"$ROOT/bin/rolangc"}
FILTER=${1:-}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
test -x "$RC" || { echo "Compiler not found: $RC (run make first or set ROLANGC)" >&2; exit 1; }

cases() { # KIND DIR: one "KIND PATH" line per case
    [ -d "$2" ] || return 0
    MULTI=$(find "$2" -name main.rl -exec dirname {} \;)
    printf '%s\n' "$MULTI" | grep . | sed "s|^|$1 |"
    # Files inside a multi-file case directory belong to that case.
    find "$2" -name '*.rl' | while read -r file; do
        inside=false
        for dir in $MULTI; do case "$file" in "$dir"/*) inside=true ;; esac; done
        $inside || echo "$1 $file"
    done
}
LIST=$( { cases run "$ROOT/tests/run"; cases fail "$ROOT/tests/compile_fail"; cases run "$ROOT/examples"; } | grep -F -- "$FILTER" | sort)
COUNT=$(printf '%s\n' "$LIST" | grep -c .)
RESULTS=$(printf '%s\n' "$LIST" | grep . | xargs -P "$JOBS" -L 1 "$ROOT/scripts/test-case.sh" "$RC")
FAILED=$(printf '%s\n' "$RESULTS" | grep '^FAIL' | sort)
if [ -n "$FAILED" ]; then printf '%s\n' "$FAILED"; fi
PASSED=$(printf '%s\n' "$RESULTS" | grep -c '^PASS')
echo "$PASSED/$COUNT tests passed"
[ "$PASSED" -eq "$COUNT" ]
