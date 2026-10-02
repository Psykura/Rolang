
struct Holder { var values: Vec<String>; }
def replace(values: Vec<String>, owner: Holder) -> String {
    owner.values = Vec<String>.new();
    return values.get(0);
}
def main() -> i32 {
    let owner = Holder { values: Vec<String>.new() };
    owner.values.push("kept");
    if !replace(owner.values, owner).equals("kept") { return 1; }
    return owner.values.len();
}
