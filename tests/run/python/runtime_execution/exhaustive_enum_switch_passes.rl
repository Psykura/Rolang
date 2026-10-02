
enum Color {
    case red;
    case green;
    case blue;
}

def main() -> i32 {
    let c = Color.red;
    switch c {
        case .red: return 0;
        case .green: return 1;
        case .blue: return 2;
    }
    return 3;
}
