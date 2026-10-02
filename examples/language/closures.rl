def make_adder(base: i32) -> (i32) -> i32 {
    (n: i32) -> { base + n }
}
def make_counter() -> () -> i32 {
    var count = 0;
    () -> { count += 1; count }
}
def apply(f: (i32) -> i32, value: i32) -> i32 { f(value) }
def twice(n: i32) -> i32 { n * 2 }

def main() -> i32 {
    let add = make_adder(40);
    let contextual: (i32) -> i32 = (n) -> { n + 1 };
    let next = make_counter();
    next();
    var total = 40;
    let bump = () -> { total += next(); };
    bump();
    if add(2) == 42 && apply(twice, 21) == 42 && contextual(41) == 42 && total == 42 { return 0; }
    1
}
