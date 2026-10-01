/* C link entry: runtime services and standard-library implementations.
 * Modules have their own headers and can also be compiled separately.
 * A unified object preserves cross-module C optimization and LTO behavior. */

#include "memory.c"
#include "panic.c"
#include "../std/string.c"
#include "../std/vec.c"
#include "../std/dict.c"
#include "../std/char.c"
#include "../std/io.c"
#include "../std/fs.c"
#include "../std/path.c"
#include "../std/process.c"
#include "../std/fmt.c"
#include "../std/panic.c"
#include "../std/sha256.c"
#include "../std/string_builder.c"
#include "scheduler.c"
#include "../std/task.c"
#include "../std/async_io.c"
#include "entry.c"
