// expect-exit: 42

struct GenPair<A, B> {
    var fst: A
    var snd: B
}

def main() -> i32 {
    let p = GenPair { fst: 10, snd: 32 };
    (p.fst + p.snd) as i32
}
