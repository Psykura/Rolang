import std.io
import std.json
import std.set
import std.toml

struct Address: Codable, Hashable { let city: String; let zip: String?; }
enum Role: Codable, Hashable { case admin; case guest; case member(i32); case pair(String, i32); case named(level: i32, title: String); }
struct User: Codable, Equatable {
    let name: String;
    let age: i32;
    var tags: Vec<String> = [];
    let address: Address?;
    let roles: [Role];
    let scores: [String: f64];
}
struct Version: Comparable, Hashable { let major: i32; let minor: i32; }
struct Box<T>: Codable, Equatable { let value: T; let items: Vec<T>; }

def main() -> i32 {
    let ada = User { name: "ada", age: 36, tags: ["math"], address: Address { city: "London", zip: nil },
        roles: [Role.admin(), Role.member(7), Role.pair("x", 2), Role.named(level: 3, title: "lead")], scores: ["a": 1.5] };
    let text = encode_json(ada);
    println(text);
    let back: Result<User, DecodeError> = decode_json(text);
    switch back { case .ok(let user): println(f"round trip {user == ada}"); case .err(let error): println(error.to_string()); }
    let minimal: Result<User, DecodeError> = decode_json("{\"name\": \"bo\", \"age\": 5, \"roles\": [\"guest\"], \"scores\": {}}");
    switch minimal { case .ok(let user): println(f"{user.name} {user.tags.len()} {user.address == nil}"); case .err(let error): println(error.to_string()); }
    for bad in ["{\"name\": \"x\"}", "{\"name\": 1, \"age\": 2, \"roles\": [], \"scores\": {}}", "{\"name\": \"x\", \"age\": 2, \"roles\": [\"boss\"], \"scores\": {}}", "{\"name\": \"x\", \"age\": 2, \"roles\": [{\"member\": \"7\"}], \"scores\": {}}"] {
        let result: Result<User, DecodeError> = decode_json(bad);
        println(result.err_value()?.to_string() ?? "accepted");
    }
    let versions = [Version { major: 1, minor: 2 }, Version { major: 0, minor: 9 }, Version { major: 1, minor: 0 }];
    let sorted = versions.sorted();
    println(f"{sorted[0].major}.{sorted[0].minor} {sorted[2].major}.{sorted[2].minor}");
    let seen = Set<Version>.new(); seen.add(Version { major: 1, minor: 0 }); seen.add(Version { major: 1, minor: 0 });
    let roles = Dict<Role, i32>.new(); roles[Role.member(1)] = 1; roles[Role.member(1)] = 2; roles[Role.member(2)] = 3;
    println(f"{seen.len()} {roles.len()}");
    let boxed = Box<i32> { value: 1, items: [2, 3] };
    println(encode_json(boxed));
    let unboxed: Result<Box<String>, DecodeError> = decode_json("{\"value\": \"v\", \"items\": [\"a\"]}");
    println(f"{unboxed.ok_value()?.value ?? "?"}");
    // The same derived conformances read TOML.
    let config: Result<Address, DecodeError> = decode_toml("city = \"Paris\"\nzip = \"75001\"\n");
    println(f"{config.ok_value()?.city ?? "?"} {config.ok_value()?.zip ?? "?"}");
    switch encode_toml(Address { city: "Rome", zip: "00100" }) { case .ok(let text): print(text); case .err(let error): println(error.to_string()); }
    // Optional elements iterate like any others.
    let maybe: Vec<String?> = [nil, "x", nil];
    var count = 0; for item in maybe { count += 1; }
    var present = 0; for item in maybe { if item != nil { present += 1; } }
    println(f"{count} {present}");
    0
}
