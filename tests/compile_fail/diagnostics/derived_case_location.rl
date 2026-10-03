// expect-error: --> derived_case_location.rl:6:10
struct Handler { let name: String; }

enum Mode: Hashable {
    case fast
    case custom(Handler)
}

def main() -> i32 { 0 }
