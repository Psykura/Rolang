import std.io
import std.fs
import std.json
def main() -> i32 {
    let text = fs_read_text("json_files/sample.json") ?? "";
    switch Json.parse(text) {
        case .ok(let doc):
            println(doc.to_string());
            println(f"{doc["name"].as_string() ?? "?"} {doc["version"].len()} {doc["version"].at(1)?.as_int() ?? -1} {doc["big"].as_int() ?? 0}");
            println(f"{doc["huge"].as_f64() ?? 0.0} {doc["missing"]["x"].is_null()} {doc["pi"].as_int() == nil} {doc.get("nested")?.get("ok")?.as_bool() ?? false}");
            println(doc["nested"].pretty());
            switch Json.parse(doc.pretty(4)) { case .ok(let again): println(f"round trip {again == doc}"); case .err(let error): println(error.to_string()); }
        case .err(let error): println(error.to_string()); return 1;
    }
    let reply = Json.empty_object();
    reply.set("ok", Json.bool(true));
    reply.set("count", Json.int(3));
    reply.set("ratio", Json.float(2.0));
    reply.set("bad", Json.float(0.0 / 0.0));
    let list = Json.empty_array();
    list.push(Json.string("a\nb\u{1}"));
    list.push(Json.null());
    reply.set("list", list);
    reply.set("count", Json.int(4));
    println(reply.to_string());
    println(json_quote("say \"hi\"\t"));
    for bad in ["{\"a\": }", "[1, 2", "\"\\x\"", "01", "{\"a\" 1}", "[1,]", "tru", "\"\\ud800\"", "1 2", "-", "1.", "1e", "\"a\nb\"", "{1: 2}", ""] {
        switch Json.parse(bad) { case .ok(let value): println("accepted " + bad); case .err(let error): println(error.to_string()); }
    }
    0
}
