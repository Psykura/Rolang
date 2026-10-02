unsafe def danger() -> i32 { 42 }
def main() -> i32 { var v = 0; unsafe { v = danger(); } if v == 42 { return 0; } 1 }
