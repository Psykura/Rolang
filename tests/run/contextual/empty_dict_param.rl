def count(d: [String: i32]) -> i64 { d.len() }
def main() -> i32 { if count([:]) == 0 { return 0; } 1 }
