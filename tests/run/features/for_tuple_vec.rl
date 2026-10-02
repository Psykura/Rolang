def pair() -> (i32, String) { (42, "answer") }
def main() -> i32 {
    let pairs = Vec<(i32, String)>.new(); pairs.push(pair());
    for (number, label) in pairs { if number != 42 || !label.equals("answer") { return 2; } }
    0
}
