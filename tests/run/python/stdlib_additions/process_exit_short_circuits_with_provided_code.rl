// expect-exit: 42

import "process.rl"

def main() -> i32 {
    process_exit(42);
    return 0;
}
