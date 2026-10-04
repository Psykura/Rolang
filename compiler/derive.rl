// Derived conformances. A struct or enum declaring Equatable, Hashable,
// Comparable, Encodable, Decodable or Codable without defining the methods
// gets them generated as Rolang source for an extension, which the parser
// reads like any other declaration. Generated code calls std helpers by name:
// hash_combine (std.compare) and Json, DecodeError and json_field (std.json).
import std.string_builder

pub struct DeriveField {
    pub let name: String;
    // The annotation's source text, e.g. "Vec<Item>" or "String?".
    pub let type_text: String;
    // The default value's source text, when the field has one.
    pub let default_text: String?;
}

pub struct DeriveCase {
    pub let name: String;
    pub let labels: Vec<String?>;
    pub let types: Vec<String>;
}

pub struct DeriveRequest {
    pub let name: String;
    pub let generic_names: Vec<String>;
    // Conformances to derive, among the names above.
    pub let protocols: Vec<String>;
    // Methods the type defines itself, which are never generated.
    pub let defined: Vec<String>;
    pub let fields: Vec<DeriveField>;
    pub let cases: Vec<DeriveCase>;
    pub let is_enum: Bool;
}

pub def derivable_protocol(name: String) -> Bool {
    name.equals("Equatable") || name.equals("Hashable") || name.equals("Comparable") ||
        name.equals("Encodable") || name.equals("Decodable") || name.equals("Codable") || name.equals("Sendable")
}

// Source of an extension declaring the conformances, with the methods the type lacks.
pub def derive_source(request: DeriveRequest) -> String {
    let wants = (name: String) -> Bool {
        for protocol in request.protocols {
            if protocol.equals(name) { return true; }
            // Codable means both directions; Comparable and Hashable need equality.
            if protocol.equals("Codable") && (name.equals("Encodable") || name.equals("Decodable")) { return true; }
            if (protocol.equals("Comparable") || protocol.equals("Hashable")) && name.equals("Equatable") { return true; }
        }
        false
    };
    let has = (method: String) -> Bool {
        for name in request.defined { if name.equals(method) { return true; } }
        false
    };
    let derive = DeriveWriter { request, out: StringBuilder.new() };
    let body = StringBuilder.new();
    if wants("Equatable") && !has("__eq__") { body.append(derive.equals()); }
    if wants("Hashable") && !has("hash") { body.append(derive.hash()); }
    if wants("Comparable") && !has("__lt__") && !request.is_enum { body.append(derive.less()); }
    if wants("Encodable") && !has("to_json") { body.append(derive.encode()); }
    if wants("Decodable") && !has("from_json") { body.append(derive.decode()); }
    if wants("Sendable") && !has("send_encode") { body.append(derive.send_encode()); }
    if wants("Sendable") && !has("send_decode") { body.append(derive.send_decode()); }
    // The extension also declares the conformances, also when the type defines every method.
    var header = "extension " + request.name;
    if request.generic_names.len() > 0 {
        let names = join_names(request.generic_names);
        header = f"extension<{names}> {request.name}<{names}>";
    }
    header + ": " + join_names(request.protocols) + " {\n" + body.to_string() + "}\n"
}

def join_names(names: Vec<String>) -> String {
    var out = "";
    for index in 0..<names.len() { if index > 0 { out += ", "; } out += names[index]; }
    out
}

def is_optional_text(text: String) -> Bool { text.trim().ends_with("?") }
def strip_optional(text: String) -> String {
    let trimmed = text.trim();
    trimmed.substring(0, (trimmed.len() as i32) - 1).trim()
}
def quote_text(text: String) -> String { "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"" }

struct DeriveWriter {
    let request: DeriveRequest;
    let out: StringBuilder;

    // The type as written inside its extension, e.g. Box<T>.
    def self_type() -> String {
        if self.request.generic_names.len() == 0 { return self.request.name; }
        self.request.name + "<" + join_names(self.request.generic_names) + ">"
    }
    // ` where T: P, U: P` for the type's parameters.
    def bounds(protocol: String) -> String {
        if self.request.generic_names.len() == 0 { return ""; }
        var out = " where ";
        for index in 0..<self.request.generic_names.len() {
            if index > 0 { out += ", "; }
            out += self.request.generic_names[index] + ": " + protocol;
        }
        out
    }
    // `let a0, let a1` for an enum case's payload.
    def bindings(prefix: String, count: i32) -> String {
        if count == 0 { return ""; }
        var out = "(";
        for index in 0..<count { if index > 0 { out += ", "; } out += f"let {prefix}{index}"; }
        out + ")"
    }

    def equals() -> String {
        let out = StringBuilder.new();
        out.append(f"    pub def __eq__(other: {self.self_type()}) -> Bool{self.bounds("Equatable")} {{\n");
        if !self.request.is_enum {
            var condition = "true";
            for field in self.request.fields { condition += f" && self.{field.name} == other.{field.name}"; }
            out.append(f"        {condition}\n    }}\n");
            return out.to_string();
        }
        out.append("        switch self {\n");
        for entry in self.request.cases {
            let count = entry.types.len();
            var condition = "true";
            for index in 0..<count { condition += f" && a{index} == b{index}"; }
            out.append(f"            case .{entry.name}{self.bindings("a", count)}: switch other {{ case .{entry.name}{self.bindings("b", count)}: return {condition}; default: return false; }}\n");
        }
        out.append("        }\n    }\n");
        out.to_string()
    }

    def hash() -> String {
        let out = StringBuilder.new();
        out.append(f"    pub def hash() -> u64{self.bounds("Hashable")} {{\n");
        if !self.request.is_enum {
            out.append("        var seed: u64 = 0;\n");
            for field in self.request.fields { out.append(self.hash_value(f"self.{field.name}", field.type_text, "        ")); }
            out.append("        seed\n    }\n");
            return out.to_string();
        }
        out.append("        var seed: u64 = 0;\n        switch self {\n");
        for case_index in 0..<self.request.cases.len() {
            let entry = self.request.cases[case_index];
            out.append(f"            case .{entry.name}{self.bindings("a", entry.types.len())}:\n");
            out.append(f"                seed = hash_combine(seed, ({case_index} as u64).hash());\n");
            for index in 0..<entry.types.len() { out.append(self.hash_value(f"a{index}", entry.types[index], "                ")); }
        }
        out.append("        }\n        seed\n    }\n");
        out.to_string()
    }
    def hash_value(value: String, type_text: String, indent: String) -> String {
        if is_optional_text(type_text) {
            return f"{indent}if let present = {value} {{ seed = hash_combine(seed, present.hash()); }} else {{ seed = hash_combine(seed, 0); }}\n";
        }
        f"{indent}seed = hash_combine(seed, {value}.hash());\n"
    }

    // Field-by-field (lexicographic) order.
    def less() -> String {
        let out = StringBuilder.new();
        out.append(f"    pub def __lt__(other: {self.self_type()}) -> Bool{self.bounds("Comparable")} {{\n");
        for field in self.request.fields {
            out.append(f"        if self.{field.name} < other.{field.name} {{ return true; }}\n");
            out.append(f"        if other.{field.name} < self.{field.name} {{ return false; }}\n");
        }
        out.append("        false\n    }\n");
        out.to_string()
    }

    // std.parallel: fields (or the case number and its payload) in order.
    def send_encode() -> String {
        let out = StringBuilder.new();
        out.append(f"    pub def send_encode(out: SendWriter) -> Void{self.bounds("Sendable")} {{\n        out.enter();\n");
        if !self.request.is_enum {
            for field in self.request.fields { out.append(f"        send_encode_value(self.{field.name}, out);\n"); }
        } else {
            out.append("        switch self {\n");
            var number = 0;
            for entry in self.request.cases {
                let count = entry.types.len();
                out.append(f"            case .{entry.name}{self.bindings("a", count)}:\n                out.put_int({number});\n");
                for index in 0..<count { out.append(f"                send_encode_value(a{index}, out);\n"); }
                number += 1;
            }
            out.append("        }\n");
        }
        out.append("        out.leave();\n    }\n");
        out.to_string()
    }
    def send_decode() -> String {
        let out = StringBuilder.new();
        let type = self.self_type();
        out.append(f"    pub static def send_decode(input: SendReader) -> {type}{self.bounds("Sendable")} {{\n");
        if !self.request.is_enum {
            var arguments = "";
            for index in 0..<self.request.fields.len() {
                let field = self.request.fields[index];
                out.append(f"        let decoded{index}: {field.type_text} = send_decode_value<{field.type_text} >(input);\n");
                if index > 0 { arguments += ", "; }
                arguments += f"{field.name}: decoded{index}";
            }
            out.append(f"        {type} {{ {arguments} }}\n    }}\n");
            return out.to_string();
        }
        out.append("        let number = input.int();\n");
        var position = 0;
        let last = self.request.cases.len() - 1;
        for entry in self.request.cases {
            let count = entry.types.len();
            // The last case takes every remaining number (the buffer comes from this program).
            let inner = position < last;
            var indent = "        ";
            if inner { out.append(f"        if number == {position} {{\n"); indent = "            "; }
            var arguments = "";
            for index in 0..<count {
                out.append(f"{indent}let value{index}: {entry.types[index]} = send_decode_value<{entry.types[index]} >(input);\n");
                if index > 0 { arguments += ", "; }
                if let label = entry.labels[index] { arguments += f"{label}: value{index}"; } else { arguments += f"value{index}"; }
            }
            var made = f"{type}.{entry.name}"; if count > 0 { made = f"{type}.{entry.name}({arguments})"; }
            if inner { out.append(f"{indent}return {made};\n        }}\n"); } else { out.append(f"{indent}{made}\n"); }
            position += 1;
        }
        out.append("    }\n");
        out.to_string()
    }

    def encode() -> String {
        let out = StringBuilder.new();
        out.append(f"    pub def to_json() -> Json{self.bounds("Encodable")} {{\n");
        if !self.request.is_enum {
            out.append("        let object = Json.empty_object();\n");
            for field in self.request.fields {
                out.append(self.encode_value(f"self.{field.name}", field.type_text, f"object.set({quote_text(field.name)}, ", "        "));
            }
            out.append("        object\n    }\n");
            return out.to_string();
        }
        out.append("        switch self {\n");
        for entry in self.request.cases {
            let count = entry.types.len();
            out.append(f"            case .{entry.name}{self.bindings("a", count)}:\n");
            if count == 0 { out.append(f"                return Json.string({quote_text(entry.name)});\n"); continue; }
            out.append("                let object = Json.empty_object();\n");
            if count == 1 && entry.labels[0] == nil {
                out.append(self.encode_value("a0", entry.types[0], f"object.set({quote_text(entry.name)}, ", "                "));
            } else if self.all_labeled(entry) {
                out.append("                let payload = Json.empty_object();\n");
                for index in 0..<count { out.append(self.encode_value(f"a{index}", entry.types[index], f"payload.set({quote_text(entry.labels[index] ?? "")}, ", "                ")); }
                out.append(f"                object.set({quote_text(entry.name)}, payload);\n");
            } else {
                out.append("                let payload = Json.empty_array();\n");
                for index in 0..<count { out.append(self.encode_value(f"a{index}", entry.types[index], "payload.push(", "                ")); }
                out.append(f"                object.set({quote_text(entry.name)}, payload);\n");
            }
            out.append("                return object;\n");
        }
        out.append("        }\n    }\n");
        out.to_string()
    }
    // `call(...)` receives the encoded value; nil becomes null.
    def encode_value(value: String, type_text: String, call: String, indent: String) -> String {
        if is_optional_text(type_text) {
            return f"{indent}if let present = {value} {{ {call}present.to_json()); }} else {{ {call}Json.null()); }}\n";
        }
        f"{indent}{call}{value}.to_json());\n"
    }
    def all_labeled(entry: DeriveCase) -> Bool {
        for index in 0..<entry.labels.len() { if entry.labels[index] == nil { return false; } }
        true
    }

    def decode() -> String {
        let out = StringBuilder.new();
        let type = self.self_type();
        let result = f"Result<{type}, DecodeError>";
        out.append(f"    pub static def from_json(value: Json) -> {result}{self.bounds("Decodable")} {{\n");
        if !self.request.is_enum {
            out.append(f"        guard let fields = value.as_object() else {{ return {result}.err(error: DecodeError.expected(\"an object\", value)); }}\n");
            var names = "";
            for index in 0..<self.request.fields.len() {
                let field = self.request.fields[index];
                let key = quote_text(field.name);
                if is_optional_text(field.type_text) {
                    out.append(f"        let decoded{index}: Result<{strip_optional(field.type_text)}?, DecodeError> = json_optional_field(fields, {key});\n");
                } else if let fallback = field.default_text {
                    out.append(f"        let decoded{index}: Result<{field.type_text}, DecodeError> = json_field_or(fields, {key}, {fallback});\n");
                } else {
                    out.append(f"        let decoded{index}: Result<{field.type_text}, DecodeError> = json_field(fields, {key});\n");
                }
                out.append(f"        let field{index} = try decoded{index};\n");
                if index > 0 { names += ", "; }
                names += f"{field.name}: field{index}";
            }
            out.append(f"        {result}.ok(value: {type} {{ {names} }})\n    }}\n");
            return out.to_string();
        }
        out.append("        if let name = value.as_string() {\n");
        for entry in self.request.cases { if entry.types.len() == 0 {
            out.append(f"            if name.equals({quote_text(entry.name)}) {{ return {result}.ok(value: {type}.{entry.name}()); }}\n");
        } }
        out.append(f"            return {result}.err(error: DecodeError.new(f\"unknown case '{{name}}'\"));\n        }}\n");
        out.append(f"        guard let object = value.as_object() else {{ return {result}.err(error: DecodeError.expected(\"a string or an object\", value)); }}\n");
        out.append(f"        if object.len() != 1 {{ return {result}.err(error: DecodeError.new(\"expected an object with one member naming the case\")); }}\n");
        out.append("        let name = object.keys()[0];\n        let payload = object[name] ?? Json.null();\n");
        for entry in self.request.cases {
            let count = entry.types.len();
            if count == 0 { continue; }
            let key = quote_text(entry.name);
            out.append(f"        if name.equals({key}) {{\n");
            var arguments = "";
            if count == 1 && entry.labels[0] == nil {
                out.append(self.decode_value(0, entry.types[0], "payload", key));
                arguments = "value0";
            } else if self.all_labeled(entry) {
                out.append(f"            guard let members = payload.as_object() else {{ return {result}.err(error: DecodeError.expected(\"an object\", payload).within({key})); }}\n");
                for index in 0..<count {
                    let label = quote_text(entry.labels[index] ?? "");
                    out.append(self.decode_value(index, entry.types[index], f"members[{label}] ?? Json.null()", key + f" + \".\" + {label}"));
                    if index > 0 { arguments += ", "; }
                    arguments += f"{entry.labels[index] ?? ""}: value{index}";
                }
            } else {
                out.append(f"            guard let items = payload.as_array() else {{ return {result}.err(error: DecodeError.expected(\"an array\", payload).within({key})); }}\n");
                out.append(f"            if items.len() != {count} {{ return {result}.err(error: DecodeError.new(\"expected {count} values\").within({key})); }}\n");
                for index in 0..<count {
                    out.append(self.decode_value(index, entry.types[index], f"items[{index}]", key + f" + \"[{index}]\""));
                    if index > 0 { arguments += ", "; }
                    arguments += f"value{index}";
                }
            }
            out.append(f"            return {result}.ok(value: {type}.{entry.name}({arguments}));\n        }}\n");
        }
        out.append(f"        {result}.err(error: DecodeError.new(f\"unknown case '{{name}}'\"))\n    }}\n");
        out.to_string()
    }
    // `let value{index} = ...` decoded from `source`, with errors placed at `path`.
    def decode_value(index: i32, type_text: String, source: String, path: String) -> String {
        let out = StringBuilder.new();
        if is_optional_text(type_text) {
            let inner = strip_optional(type_text);
            out.append(f"            var value{index}: {inner}? = nil;\n");
            out.append(f"            let raw{index} = {source};\n");
            out.append(f"            if !raw{index}.is_null() {{\n");
            out.append(f"                let decoded{index}: Result<{inner}, DecodeError> = json_decode(raw{index});\n");
            out.append(f"                switch decoded{index} {{ case .ok(let present): value{index} = present; case .err(let error): return Result<{self.self_type()}, DecodeError>.err(error: error.within({path})); }}\n");
            out.append("            }\n");
            return out.to_string();
        }
        out.append(f"            let decoded{index}: Result<{type_text}, DecodeError> = json_decode({source});\n");
        out.append(f"            var value{index}: {type_text};\n");
        out.append(f"            switch decoded{index} {{ case .ok(let present): value{index} = present; case .err(let error): return Result<{self.self_type()}, DecodeError>.err(error: error.within({path})); }}\n");
        out.to_string()
    }
}
