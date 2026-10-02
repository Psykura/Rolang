// expect-error: Cannot assign String to i32 in variable initializer
// Undefined names do not stop type checking of the rest of the program.
def main() -> i32 {
    let a = missing;
    let b: i32 = "text";
    0
}
