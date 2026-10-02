// expect-exit: 35

import "iter.rl"

def main() -> i32 {
    var sum: i32 = 0;
    for i in 5..<10 {
        sum = sum + i;
    }
    return sum;
}
