extern "C" def abs(x: i32) -> i32;
def main() -> i32 { var r = 0; unsafe { r = abs(-42); } if r == 42 { return 0; } 1 }
