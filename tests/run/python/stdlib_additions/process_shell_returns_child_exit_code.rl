// expect-exit: 7

import "process.rl"

def main() -> i32 {
    return shell("exit 7");
}
