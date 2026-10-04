import std.io
import std.csv
import std.json
struct Person: Codable { let name: String; let age: i32; let note: String?; }
def show(text: String) -> Void {
    switch parse_csv(text) {
        case .ok(let rows):
            var out = "";
            for row in rows { out = out + "["; for f in row { out = out + "<" + f.replace("\n", "\\n") + ">"; } out = out + "]"; }
            println(f"{rows.len()} {out}");
        case .err(let e): println(e.to_string());
    }
}
def main() -> i32 {
    show("a,b,c\n1,2,3\n");
    show("a,b\r\n\"x, y\",\"say \"\"hi\"\"\"\r\n");
    show("\"multi\nline\",z\n,\n");
    show("one");
    show("");
    show("a,\"b\"c\n");
    show("a,b\"c\n");
    show("x,\"open\n");
    switch csv_records("name,age\nada,36\ngrace,85\n") {
        case .ok(let records): for r in records { println(f"{r["name"] ?? "?"} is {r["age"] ?? "?"}"); }
        case .err(let e): println(e.to_string());
    }
    println(csv_records("a,b\n1\n").err_value()?.to_string() ?? "-");
    let text = write_csv([["name", "note"], ["ada", "says \"hi\", twice"], ["x", " padded"], ["multi", "a\nb"]]);
    print(text);
    let back = parse_csv(text).ok_value() ?? [];
    println(f"{back.len()} {back[1][1]} {back[3][1].len()}");
    print(write_csv([["a", "b;c"]], delimiter: ";"));
    print(encode_csv([Person { name: "ada", age: 36, note: nil }, Person { name: "grace", age: 85, note: "cobol, compilers" }]));
    0
}
