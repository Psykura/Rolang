
import "string.rl"

extern "C" def rt_obj_live_count() -> i64;

def take(s: String) -> i64 { return s.len(); }

def main() -> i32 {
    var acc: i64 = 0;
    var i: i64 = 0;
    while i < 50000 {
        acc = acc + take("x");        // borrowed call argument
        acc = acc + "yz".len();       // borrowed method receiver
        let z = "a" + "b";            // borrowed operands of `+`
        acc = acc + z.len();
        i = i + 1;
    }
    var live: i64 = 1000000;
    unsafe { live = rt_obj_live_count(); }
    if live > 1000 { return 1; }
    if acc < 0 { return 2; }  // keep `acc` (and the literal evaluations) live
    return 0;
}
