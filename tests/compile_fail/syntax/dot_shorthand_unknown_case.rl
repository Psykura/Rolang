// expect-error: has no case 'quick'
enum Mode { case fast; case slow; }
def main() -> i32 {
    let mode: Mode = .quick;
    0
}
