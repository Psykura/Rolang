struct Label { var text: String;
    def prefixed(with p: String) -> String { p + self.text }
    def touch() -> Void { self.text = self.text + "!"; } }
def make() -> Label { Label { text: "made" } }
def apply(f: (String) -> String) -> String { f("> ") }
def main() -> i32 {
    let l = Label { text: "a" };
    let pre = l.prefixed;
    let touch = l.touch;
    touch(); touch();
    let maybe: Label? = l;
    let opt = maybe?.prefixed;
    let fresh = make().prefixed;
    if pre("x") == "xa!!" && apply(fresh) == "> made" && (opt ?? ((s) -> { "" }))("") == "a!!" { return 0; }
    1
}
