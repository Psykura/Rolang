// expect-error: Cannot assign i32 to String in tuple element 1
def main() -> i32 { let a: (i32, String) = (1, 2); 0 }
