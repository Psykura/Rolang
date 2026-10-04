// expect-error: '.fast' needs a context that expects an enum type
enum Mode { case fast; case slow; }
def main() -> i32 {
    let mode = .fast;
    0
}
