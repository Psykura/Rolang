// expect-error: Cannot assign T to i32 in assignment
def g<T>(t: T) -> Void { var n: i32 = 0; n = t; }
def main() -> i32 { g(1); 0 }
