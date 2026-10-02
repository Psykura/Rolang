// expect-exit: 17

import "calc.rl"

def main() -> i32 {
    var a = square(3);
    var b = cube(2);
    return a + b;
}
