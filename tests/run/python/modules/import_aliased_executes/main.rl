// expect-exit: 42

import "math.rl" as m

def main() -> i32 {
    var a = m.square(5);
    return m.add(a, 17);
}
