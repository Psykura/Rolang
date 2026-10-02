// expect-exit: 6

import "io.rl"

def main() -> i32 {
    let s = "ab";
    let r = s.repeat(3);
    println(r);  // "ababab"
    return r.len() as i32;
}
