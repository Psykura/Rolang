// Standard library: command-line argument parsing.
//
//     let cli = CommandLine.new("greet", "[options] NAME");
//     cli.flag("loud", "print in capitals").short("l");
//     cli.option("times", "N", "repeat N times").short("n");
//     cli.positional("name", "who to greet");
//     guard let args = cli.parse_process() else { return cli.status; }
//     let times = (args.value("times") ?? "1").to_i32();
//
// Options are spelled `--name value`, `--name=value`, `-n value` or `-nvalue`;
// short flags combine (`-lv`). `--` ends options. An option may be repeated:
// `value` returns the last occurrence and `values` all of them. `-h`/`--help`
// and `--version` (when a version is set) are built in.
import "string.rl"
import "vec.rl"
import "range.rl"
import "dict.rl"
import "result.rl"
import "io.rl"
import "process.rl"
import "string_builder.rl"

// An extra spelling that sets its option to a fixed value, e.g. `--no-lto` for `--lto=none`.
pub struct CliPreset {
    pub let spellings: Vec<String>;
    pub let value: String;
    pub let help: String;
}

pub struct CliOption {
    pub let name: String;
    // Value placeholder for help; empty for flags.
    pub let value_name: String;
    pub let help: String;
    pub var short_name: String;
    pub var hidden: Bool;
    pub var allow_empty: Bool;
    // Value used when the option is given without `=value`; empty when a value is required.
    pub var implicit_value: String;
    pub let allowed: Vec<String>;
    pub let presets: Vec<CliPreset>;

    pub def takes_value() -> Bool { self.value_name.len() > 0 }
    // `-x` spelling; one character.
    pub def short(name: String) -> CliOption { self.short_name = name; self }
    // Accepted but not listed in help.
    pub def hide() -> CliOption { self.hidden = true; self }
    pub def empty_allowed() -> CliOption { self.allow_empty = true; self }
    // Restricts values to `values`.
    pub def choices(values: Vec<String>) -> CliOption {
        for value in values { self.allowed.push(value); }
        self
    }
    // Makes the value optional: `--name` alone means `value`; a value must use `--name=value`.
    pub def implicit(value: String) -> CliOption { self.implicit_value = value; self }
    pub def preset(spellings: Vec<String>, value: String, help: String = "") -> CliOption {
        self.presets.push(CliPreset { spellings, value, help });
        self
    }
    def spelling() -> String { "--" + self.name }
}

pub struct CliPositional {
    pub let name: String;
    pub let help: String;
    pub var required: Bool;
    pub var many: Bool;

    pub def optional() -> CliPositional { self.required = false; self }
    // Collects every remaining argument.
    pub def variadic() -> CliPositional { self.many = true; self }
}

// One option occurrence in command-line order.
pub struct CliMatch {
    pub let name: String;
    pub let value: String;
    // The spelling used, such as `-o` or `--no-lto`.
    pub let spelling: String;
}

pub struct CliArgs {
    pub let matches: Vec<CliMatch>;
    let positional_values: Dict<String, Vec<String>>;

    pub def has(name: String) -> Bool { self.count(name) > 0 }
    pub def count(name: String) -> i32 {
        var count = 0;
        for found in self.matches { if found.name.equals(name) { count += 1; } }
        count
    }
    // The last value given for an option or positional argument.
    pub def value(name: String) -> String? {
        let values = self.values(name);
        if values.len() == 0 { return nil; }
        values[values.len() - 1]
    }
    // Every value given, in order.
    pub def values(name: String) -> Vec<String> {
        if let positional = self.positional_values[name] { return positional; }
        let values = Vec<String>.new();
        for found in self.matches { if found.name.equals(name) { values.push(found.value); } }
        values
    }
}

pub struct CommandLine {
    pub let name: String;
    pub let usage: String;
    pub var about: String;
    pub var version: String;
    // Exit status after parse_process returns nil: 0 for help/version, 2 for errors.
    pub var status: i32;
    let options: Vec<CliOption>;
    let positionals: Vec<CliPositional>;
    let exclusive_groups: Vec<Vec<String>>;

    // `usage` follows the program name in help, e.g. "[options] input.rl".
    pub static def new(name: String, usage: String = "[options]") -> CommandLine {
        CommandLine { name, usage, about: "", version: "", status: 0, options: Vec<CliOption>.new(),
                      positionals: Vec<CliPositional>.new(), exclusive_groups: Vec<Vec<String>>.new() }
    }

    pub def flag(name: String, help: String) -> CliOption { self.add(name, "", help) }
    pub def option(name: String, value_name: String, help: String) -> CliOption { self.add(name, value_name, help) }
    pub def positional(name: String, help: String = "") -> CliPositional {
        let positional = CliPositional { name, help, required: true, many: false };
        self.positionals.push(positional);
        positional
    }
    // The named options cannot be combined; repeating one with the same value is allowed.
    pub def exclusive(names: Vec<String>) -> Void { self.exclusive_groups.push(names); }

    def add(name: String, value_name: String, help: String) -> CliOption {
        let option = CliOption { name, value_name, help, short_name: "", hidden: false,
            allow_empty: false, implicit_value: "", allowed: Vec<String>.new(), presets: Vec<CliPreset>.new() };
        self.options.push(option);
        option
    }

    // Parses the process arguments. Help and the version go to stdout, errors
    // with a hint to stderr; it then returns nil and sets `status`.
    pub def parse_process() -> CliArgs? {
        switch self.parse(arguments()) {
            case .ok(let args):
                if args.has("help") { print(self.help()); self.status = 0; return nil; }
                if args.has("version") { println(self.version); self.status = 0; return nil; }
                self.status = 0;
                return args;
            case .err(let message):
                eprintln(f"{self.name}: {message}");
                eprintln(f"Try '{self.name} --help' for more information.");
                self.status = 2;
                return nil;
        }
    }

    // Parses `arguments` (without the program name). `--help` and `--version`
    // are reported as the "help" and "version" flags without further checks.
    pub def parse(arguments: Vec<String>) -> Result<CliArgs, String> {
        let matches = Vec<CliMatch>.new();
        let loose = Vec<String>.new();
        var index = 0;
        var only_positionals = false;
        while index < arguments.len() {
            let arg = arguments[index];
            index += 1;
            if only_positionals || arg.len() < 2 || !arg.starts_with("-") { loose.push(arg); continue; }
            if arg.equals("--") { only_positionals = true; continue; }
            if arg.equals("--help") || arg.equals("-h") {
                matches.push(CliMatch { name: "help", value: "", spelling: arg }); continue;
            }
            if arg.equals("--version") && self.version.len() > 0 {
                matches.push(CliMatch { name: "version", value: "", spelling: arg }); continue;
            }
            if let preset = self.find_preset(arg) { matches.push(preset); continue; }
            if arg.starts_with("--") {
                var spelling = arg;
                var attached: String? = nil;
                let equals = arg.find("=");
                if equals >= 0 {
                    spelling = arg.substring(0, equals);
                    attached = arg.substring(equals + 1, (arg.len() as i32) - equals - 1);
                }
                guard let option = self.find_long(spelling) else { return self.unknown(spelling); }
                switch self.take_value(option, spelling, attached, arguments, index) {
                    case .ok(let taken):
                        if taken.1 { index += 1; }
                        matches.push(CliMatch { name: option.name, value: taken.0, spelling });
                    case .err(let message): return Result<CliArgs, String>.err(error: message);
                }
                continue;
            }
            // Short options: `-v`, `-vc` (flags), `-o FILE`, `-oFILE`.
            let length = arg.len() as i32;
            var at = 1;
            while at < length {
                let letter = arg.substring(at, 1);
                let spelling = "-" + letter;
                guard let option = self.find_short(letter) else { return self.unknown(spelling); }
                at += 1;
                if !option.takes_value() {
                    matches.push(CliMatch { name: option.name, value: "", spelling });
                    continue;
                }
                var attached: String? = nil;
                if at < length { attached = arg.substring(at, length - at); }
                switch self.take_value(option, spelling, attached, arguments, index) {
                    case .ok(let taken):
                        if taken.1 { index += 1; }
                        matches.push(CliMatch { name: option.name, value: taken.0, spelling });
                    case .err(let message): return Result<CliArgs, String>.err(error: message);
                }
                break;
            }
        }
        let positional_values = Dict<String, Vec<String>>.new();
        let args = CliArgs { matches, positional_values };
        if args.has("help") || args.has("version") { return Result<CliArgs, String>.ok(value: args); }
        if let problem = self.validate(matches) { return Result<CliArgs, String>.err(error: problem); }
        var next = 0;
        for positional in self.positionals {
            let values = Vec<String>.new();
            if positional.many {
                while next < loose.len() { values.push(loose[next]); next += 1; }
            } else if next < loose.len() {
                values.push(loose[next]); next += 1;
            }
            if values.len() == 0 && positional.required {
                return Result<CliArgs, String>.err(error: f"missing required argument '{positional.name}'");
            }
            positional_values[positional.name] = values;
        }
        if next < loose.len() { return Result<CliArgs, String>.err(error: f"unexpected argument '{loose[next]}'"); }
        Result<CliArgs, String>.ok(value: args)
    }

    // The option's value and whether it consumed the next argument.
    def take_value(option: CliOption, spelling: String, attached: String?, arguments: Vec<String>,
                   index: i32) -> Result<(String, Bool), String> {
        if !option.takes_value() {
            if let given = attached { return Result<(String, Bool), String>.err(error: f"option '{spelling}' does not take a value"); }
            return Result<(String, Bool), String>.ok(value: ("", false));
        }
        var value = "";
        var consumed = false;
        if let given = attached { value = given; }
        else if option.implicit_value.len() > 0 { value = option.implicit_value; }
        else if index < arguments.len() { value = arguments[index]; consumed = true; }
        else { return Result<(String, Bool), String>.err(error: f"option '{spelling}' requires a value {option.value_name}"); }
        if value.len() == 0 && !option.allow_empty {
            return Result<(String, Bool), String>.err(error: f"option '{spelling}' requires a nonempty value {option.value_name}");
        }
        if option.allowed.len() > 0 && !contains_text(option.allowed, value) {
            return Result<(String, Bool), String>.err(error: f"invalid value '{value}' for '{spelling}'; expected one of: {joined(option.allowed, ", ")}");
        }
        Result<(String, Bool), String>.ok(value: (value, consumed))
    }

    def validate(matches: Vec<CliMatch>) -> String? {
        for group in self.exclusive_groups {
            var first: CliMatch? = nil;
            for found in matches { if contains_text(group, found.name) {
                if let previous = first {
                    if !(previous.name.equals(found.name) && previous.value.equals(found.value)) {
                        return f"options '{previous.spelling}' and '{found.spelling}' cannot be used together";
                    }
                } else { first = found; }
            } }
        }
        nil
    }

    def find_preset(arg: String) -> CliMatch? {
        for option in self.options { for preset in option.presets {
            if contains_text(preset.spellings, arg) { return CliMatch { name: option.name, value: preset.value, spelling: arg }; }
        } }
        nil
    }
    def find_long(spelling: String) -> CliOption? {
        for option in self.options { if option.spelling().equals(spelling) { return option; } }
        nil
    }
    def find_short(letter: String) -> CliOption? {
        for option in self.options { if option.short_name.equals(letter) { return option; } }
        nil
    }

    def unknown(spelling: String) -> Result<CliArgs, String> {
        var message = f"unknown option '{spelling}'";
        var best = "";
        var best_distance = 3;
        for candidate in self.spellings() {
            let distance = edit_distance(spelling, candidate);
            if distance < best_distance { best = candidate; best_distance = distance; }
        }
        if best.len() > 0 { message += f"; did you mean '{best}'?"; }
        Result<CliArgs, String>.err(error: message)
    }
    def spellings() -> Vec<String> {
        let all = ["--help"];
        if self.version.len() > 0 { all.push("--version"); }
        for option in self.options {
            if option.hidden { continue; }
            all.push(option.spelling());
            for preset in option.presets { for spelling in preset.spellings { all.push(spelling); } }
        }
        all
    }

    // The help text: usage, description, arguments and options.
    pub def help() -> String {
        let out = StringBuilder.new();
        out.append_line(f"usage: {self.name} {self.usage}");
        if self.about.len() > 0 { out.append_line(""); out.append_line(self.about); }
        let rows = Vec<(String, String)>.new();
        for positional in self.positionals { if positional.help.len() > 0 { rows.push((positional.name, positional.help)); } }
        if rows.len() > 0 { out.append_line(""); out.append_line("Arguments:"); self.table(out, rows); }
        let options = Vec<(String, String)>.new();
        for option in self.options {
            if option.hidden { continue; }
            var left = "    ";
            if option.short_name.len() > 0 { left = f"-{option.short_name}, "; }
            left += option.spelling();
            if option.takes_value() {
                if option.implicit_value.len() > 0 { left += f"[={option.value_name}]"; } else { left += " " + option.value_name; }
            }
            var help = option.help;
            if option.allowed.len() > 0 { help += f" [{joined(option.allowed, "|")}]"; }
            options.push((left, help));
            for preset in option.presets { if preset.help.len() > 0 {
                options.push((joined(preset.spellings, ", "), preset.help));
            } }
        }
        options.push(("-h, --help", "print this help"));
        if self.version.len() > 0 { options.push(("    --version", "print the version")); }
        out.append_line(""); out.append_line("Options:"); self.table(out, options);
        out.to_string()
    }
    def table(out: StringBuilder, rows: Vec<(String, String)>) -> Void {
        var width = 0;
        for row in rows {
            let size = row.0.len() as i32;
            if size > width && size <= 28 { width = size; }
        }
        for row in rows {
            let size = row.0.len() as i32;
            if row.1.len() == 0 { out.append_line("  " + row.0); continue; }
            if size > width { out.append_line("  " + row.0); out.append_line("  " + " ".repeat(width + 2) + row.1); continue; }
            out.append_line("  " + row.0 + " ".repeat(width - size + 2) + row.1);
        }
    }
}

def contains_text(values: Vec<String>, wanted: String) -> Bool {
    for value in values { if value.equals(wanted) { return true; } }
    false
}

def joined(values: Vec<String>, separator: String) -> String {
    let out = StringBuilder.new();
    for value in values { if out.len() > 0 { out.append(separator); } out.append(value); }
    out.to_string()
}

// Levenshtein distance between byte strings.
def edit_distance(a: String, b: String) -> i32 {
    let rows = a.len() as i32;
    let columns = b.len() as i32;
    let previous = Vec<i32>.new();
    for j in 0...columns { previous.push(j); }
    for i in 1...rows {
        let current = [i];
        for j in 1...columns {
            var cost = 1;
            if a.byte_at(i - 1) == b.byte_at(j - 1) { cost = 0; }
            var best = previous[j - 1] + cost;
            if previous[j] + 1 < best { best = previous[j] + 1; }
            if current[j - 1] + 1 < best { best = current[j - 1] + 1; }
            current.push(best);
        }
        for j in 0..<current.len() { previous[j] = current[j]; }
    }
    previous[columns]
}
