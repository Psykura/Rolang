import std.io
import std.regex
def show(pattern: String, text: String) -> Void {
    switch Regex.new(pattern) {
        case .ok(let re):
            if let m = re.find(text) {
                var groups = "";
                for g in m.groups() { groups = groups + "|" + (g ?? "nil"); }
                println(f"{pattern} on {text}: [{m.text()}] at {m.start()}..{m.end()}{groups}");
            } else { println(f"{pattern} on {text}: no match"); }
        case .err(let e): println(e.message);
    }
}
def main() -> i32 {
    show(r"\d+", "abc 123 def");
    show(r"(\w+)@(\w+)\.com", "mail ro@lang.com now");
    show(r"^abc$", "abc");
    show(r"a.c", "a\nc");
    show(r"(?s)a.c", "a\nc");
    show(r"(?i)hello", "Say HeLLo");
    show(r"colou?r", "color");
    show(r"a{2,3}", "aaaa");
    show(r"a{2,3}?", "aaaa");
    show(r"<.+>", "<a><b>");
    show(r"<.+?>", "<a><b>");
    show(r"(a|ab)(c|bcd)(d*)", "abcd");
    show(r"\bcat\b", "concat cat");
    show(r"[^a-c]+", "abcdefabc");
    show(r"[\d\s]+", "x 1 2 3y");
    show(r"(x)?y", "y");
    show(r"é+", "café été");
    show(r"[à-ü]+", "naïve");
    show(r"(a*)*b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac");
    show(r"(?m)^\w+$", "one\ntwo");
    show(r"\x41\x{1F600}", "A😀");
    for bad in [r"(abc", r"abc)", r"[a-", r"*a", r"a{3,2}", r"\q", r"(?<n>a)(?<n>b)"] {
        switch Regex.new(bad) { case .ok(let r): println(f"{bad} compiled?"); case .err(let e): println(e.message); }
    }
    guard let date = Regex.new(r"(?<year>\d{4})-(?<month>\d\d)-(?<day>\d\d)").ok_value() else { return 1; }
    let text = "from 2026-10-04 to 2027-01-31.";
    println(date.replace_all(text, "${day}.${month}.${year}"));
    println(date.replace(text, "[$0] $$"));
    println(f"{date.find_all(text).len()} {date.find(text)?.named("month") ?? "-"} {date.group_names().len()}");
    guard let comma = Regex.new(r"\s*,\s*").ok_value() else { return 1; }
    for part in comma.split("a , b,c ,d") { print(f"<{part}>"); }
    println("");
    guard let empty = Regex.new(r"x*").ok_value() else { return 1; }
    println(empty.replace_all("abc", "-"));
    guard let words = Regex.new(r"\w+").ok_value() else { return 1; }
    println(words.replace_with("hello big world", (m) -> { m.text().uppercased() }));
    println(regex_escape("a.b*c"));
    println(f"{Regex.new(regex_escape("1+1=2")).ok_value()?.is_match("is 1+1=2?") ?? false}");
    0
}
