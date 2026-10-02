import std.task
def work(n: i32) async -> i32 { n * 2 }
def main() -> i32 { let t = spawn work(21); t.wait_blocking(); 0 }
