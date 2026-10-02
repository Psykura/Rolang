#!/bin/bash
# Runs one test case and prints "PASS name" or "FAIL name: reason".
#   test-case.sh RC KIND PATH
# KIND is "run" (must compile and exit with the expected status, optionally
# printing NAME.stdout) or "fail" (must not compile; output contains the
# `// expect-error:` text). PATH is a .rl file or a directory with main.rl.
RC=$1 KIND=$2 CASE=$3
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NAME=${CASE#"$ROOT"/}
if [ -d "$CASE" ]; then DIR=$CASE; SOURCE=$CASE/main.rl; EXPECTED=$CASE/main.stdout
else DIR=$(dirname "$CASE"); SOURCE=$CASE; EXPECTED=${CASE%.rl}.stdout; fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rolang-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
header() { sed -n "s|^// $1: ||p" "$SOURCE" | head -1; }

OUTPUT=$(cd "$DIR" && "$RC" "$SOURCE" -o "$WORK/program" 2>&1); STATUS=$?
if [ "$KIND" = fail ]; then
    WANT=$(header expect-error)
    if [ -z "$WANT" ]; then echo "FAIL $NAME: missing // expect-error: header"; exit 0; fi
    if [ $STATUS -eq 0 ]; then echo "FAIL $NAME: compiled, expected error: $WANT"; exit 0; fi
    case "$OUTPUT" in *"$WANT"*) echo "PASS $NAME" ;; *) echo "FAIL $NAME: expected error '$WANT', got: $(echo "$OUTPUT" | grep -v 'argument unused' | grep -v '^$' | head -2 | tr '\n' ' ')" ;; esac
    exit 0
fi
if [ $STATUS -ne 0 ]; then echo "FAIL $NAME: compile error: $(echo "$OUTPUT" | grep -v 'argument unused' | grep -v '^$' | head -2 | tr '\n' ' ')"; exit 0; fi
WANT_EXIT=$(header expect-exit); WANT_EXIT=${WANT_EXIT:-0}
ACTUAL=$(cd "$DIR" && perl -e 'alarm 30; exec @ARGV' "$WORK/program" 2>/dev/null); EXIT=$?
if [ "$EXIT" != "$WANT_EXIT" ]; then echo "FAIL $NAME: exit status $EXIT, expected $WANT_EXIT"; exit 0; fi
if [ -f "$EXPECTED" ] && [ "$ACTUAL" != "$(cat "$EXPECTED")" ]; then echo "FAIL $NAME: stdout differs from $(basename "$EXPECTED")"; exit 0; fi
echo "PASS $NAME"
