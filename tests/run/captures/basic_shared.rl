struct A { var v: i32; }
def main() -> i32 {
    var n = 40;
    let inc = () -> { n += 1; };
    inc(); inc();
    if n != 42 { return 1; }
    var x = 1;
    let read = () -> { x };
    x = 42;
    if read() != 42 { return 2; }
    var obj = A { v: 1 };
    let replace = () -> { obj = A { v: 42 }; };
    replace();
    if obj.v != 42 { return 3; }
    var total = 0;
    let add = (k: i32) -> { total += k; };
    let sub = (k: i32) -> { total -= k; };
    add(50); sub(8);
    if total != 42 { return 4; }
    0
}
