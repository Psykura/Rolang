// expect-error: add a `default` case
def main() -> i32 {
    let x = 3;
    let name = switch x { case 0...9: "digit"; case 10...99: "two digits"; };
    0
}
