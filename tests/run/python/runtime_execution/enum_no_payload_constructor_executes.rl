// expect-exit: 2

enum Color {
    case red
    case green
    case blue
}

def main() -> i32 {
    let c = Color.green;
    switch c {
    case .red: return 1;
    case .green: return 2;
    case .blue: return 3;
    }
}
