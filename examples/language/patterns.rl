enum Token { case number(i32); case empty; }

def read(token: Token) -> i32 {
    switch token {
        case .number(let n) where n > 0: n;
        case .number(let n): -n;
        case .empty: 0;
    }
}

def main() -> i32 {
    let name = switch Token.number(42) {
        case .number(let n): f"value={n}";
        case .empty: "empty";
    };
    if read(Token.number(-42)) == 42 && name.equals("value=42") { return 0; }
    1
}
