struct Config { var retries: i32 = 3; var name: String = "x"; var port: i32; }
def main() -> i32 { let c = Config { port: 39 }; if c.retries + c.port == 42 && c.name == "x" { return 0; } 1 }
