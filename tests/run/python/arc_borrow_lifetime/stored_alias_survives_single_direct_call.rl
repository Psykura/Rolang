
struct Scanner { var tokens: Vec<i32>; }
struct Result { var tokens: Vec<i32>; var error: String; }
def scan() -> Result {
    let tokens = Vec<i32>.new();
    let scanner = Scanner { tokens: tokens };
    scanner.tokens.push(41);
    tokens.push(42);
    return Result { tokens: tokens, error: "" };
}
def main() -> i32 {
    let result = scan();
    if result.tokens.len() != 2 { return 1; }
    return result.tokens.get(1) - 42;
}
