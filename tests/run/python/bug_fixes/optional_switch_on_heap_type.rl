// expect-exit: 42

struct Wrap { var n: i32 }
def first() -> Wrap? { Wrap { n: 30 } }
def second() -> Wrap? { nil }

def main() -> i32 {
    let a = first();
    let b = second();

    var total: i32 = 0;
    switch a {
        case .Some(let w): total = total + w.n;
        case .None: total = total + 1000;
    }
    switch b {
        case .Some(let w): total = total + w.n;
        case .None: total = total + 12;
    }
    return total;
}
