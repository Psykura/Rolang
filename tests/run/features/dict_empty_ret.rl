def make() -> [String: i32] { [:] }
def main() -> i32 { let d = make(); d["a"] = 42; if (d["a"] ?? 0) == 42 { return 0; } 1 }
