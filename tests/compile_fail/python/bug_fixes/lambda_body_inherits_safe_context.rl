// expect-error: INVALID_OPERATION: calling external 'C' function is unsafe and must be used inside an unsafe block

extern "C" def rt_panic(msg: RawPtr) -> Void;

def make() -> (i32) -> i32 {
    var bomb: (i32) -> i32 = (x: i32) -> { return x; };
    unsafe {
        bomb = (x: i32) -> { rt_panic(nil as RawPtr); return x; };
    }
    return bomb;
}

def main() -> i32 {
    let f = make();
    return 0;
}
