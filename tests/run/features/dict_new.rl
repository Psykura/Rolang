def main() -> i32 { let d = Dict<String, i32>.new(); d["a"] = 42; if (d["a"] ?? 0) == 42 { return 0; } 1 }
