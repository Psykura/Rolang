# Tests

`make test` builds bin/rolangc if needed and runs every case in parallel with
scripts/test.sh. Pass a path fragment to run a subset, for example
`scripts/test.sh tests/run/captures`; set ROLANGC to test another compiler.

| Directory | Cases |
| --- | --- |
| run/ | Programs that must compile and run. The exit status must be 0 unless the file starts with `// expect-exit: N`; a sibling NAME.stdout (or main.stdout) must match the output exactly. |
| compile_fail/ | Programs that must be rejected. The first line `// expect-error: TEXT` gives text the compiler output must contain. |
| ../examples/ | Examples, which must compile and exit with status 0. |

A directory containing main.rl is a single multi-file case: main.rl is compiled
from that directory and the other .rl files are its imports.

run/python/ and compile_fail/python/ hold programs from the original Python
implementation's test suite; their expected status and output are the Python
compiler's results. Other directories are grouped by language area.

Add a case for every fixed bug and new language feature. `make check-selfhost`
separately requires the compiler to reproduce itself bit for bit.
