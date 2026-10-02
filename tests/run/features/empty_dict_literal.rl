def main() -> i32 { var d: [String: i32] = [:]; d["a"] = 42; if (d["a"] ?? 0) == 42 { return 0; } 1 }
