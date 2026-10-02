def main() -> i32 { let v: i32? = 7; let e: i32? = nil; if v.is_some() && e.is_none() && e.unwrap_or(35) + v.unwrap_or(0) == 42 { return 0; } 1 }
