// expect-error: can only be called from an async function
def double(x: i32) async -> i32 { x * 2 }
def main() -> i32 { let f = double; f(1) }
