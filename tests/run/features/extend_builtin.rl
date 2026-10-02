extension i32 { def double() -> i32 { self * 2 } }
extension String { def shout() -> String { self + "!" } }
def main() -> i32 { if 21.double() == 42 && "a".shout() == "a!" { return 0; } 1 }
