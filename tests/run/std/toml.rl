import std.io
import std.fs
import std.json
import std.toml
def main() -> i32 {
    switch Toml.parse(fs_read_text("toml_files/config.toml") ?? "") {
        case .ok(let config):
            println(config.to_string());
            println(f"{config["server"]["ports"].at(1)?.as_int() ?? 0} {config["users"].at(1)?.get("site")?.get("name")?.as_string() ?? "?"} {config["server"]["limits"]["timeout"].as_f64() ?? 0.0}");
            switch Toml.encode(config) {
                case .ok(let text):
                    print(text);
                    switch Toml.parse(text) { case .ok(let again): println(f"round trip {again == config}"); case .err(let error): println(error.to_string()); }
                case .err(let error): println(error.to_string());
            }
        case .err(let error): println(error.to_string()); return 1;
    }
    for bad in ["a = 1\na = 2", "[t]\n[t]", "x = [1,", "n = 01", "s = \"\\q\"", "d = 2023-02-30", "a.b = 1\n[a]", "t = {a = 1}\nt.b = 2"] {
        switch Toml.parse(bad) { case .ok(let value): println("accepted"); case .err(let error): println(error.to_string()); }
    }
    let nothing = Json.empty_object(); nothing.set("x", Json.null());
    switch Toml.encode(nothing) { case .ok(let text): println(text); case .err(let error): println(error.to_string()); }
    0
}
