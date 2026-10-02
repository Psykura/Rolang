// expect-error: Cannot assign (i32) -> i32 to async (i32) -> i32
def main() async -> i32 { let f: (i32) async -> i32 = (x: i32) -> i32 { x }; await f(1) }
