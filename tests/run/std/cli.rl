import std.cli
import std.io

def spec() -> CommandLine {
    let cli = CommandLine.new("tool", "[options] FILE...");
    cli.version = "tool 1.0";
    cli.about = "Processes files.";
    cli.positional("FILE", "input files", variadic: true);
    cli.option("output", "PATH", "where to write", short: "o");
    cli.flag("verbose", "more output", short: "v");
    cli.flag("quiet", "less output", short: "q");
    cli.option("level", "N", "level", short: "L", choices: ["1", "2", "3"]);
    cli.option("lto", "MODE", "link-time optimization", choices: ["full", "thin", "none"], implicit: "full").preset(["--no-lto"], "none");
    cli.option("define", "NAME", "define a name", short: "D");
    cli.option("secret", "X", "hidden", hidden: true);
    cli.exclusive(["verbose", "quiet"]);
    cli
}

def error_of(arguments: Vec<String>) -> String {
    switch spec().parse(arguments) {
        case .ok(let args): return "ok";
        case .err(let message): return message;
    }
}

def main() -> i32 {
    let cli = spec();
    switch cli.parse(["-v", "--output=out.txt", "a.rl", "-L2", "-DX", "--define", "Y", "--", "-b.rl", "--lto", "--no-lto"]) {
        case .err(let message): println(message); return 1;
        case .ok(let args):
            if !args.has("verbose") || args.has("quiet") { return 2; }
            if !(args.value("output") ?? "").equals("out.txt") { return 3; }
            if !(args.value("level") ?? "").equals("2") { return 4; }
            let defines = args.values("define");
            if defines.len() != 2 || !defines[0].equals("X") || !defines[1].equals("Y") { return 5; }
            // Everything after `--` is positional.
            let files = args.values("FILE");
            if files.len() != 4 || !files[1].equals("-b.rl") || !files[3].equals("--no-lto") { return 6; }
            if args.has("lto") { return 7; }
    }
    switch cli.parse(["--lto", "x", "--no-lto", "-vo", "o"]) {
        case .err(let message): println(message); return 8;
        case .ok(let args):
            // Values keep command-line order, so the last spelling wins.
            if !(args.value("lto") ?? "").equals("none") { return 9; }
            if !(args.value("output") ?? "").equals("o") || !args.has("verbose") { return 10; }
    }
    switch cli.parse(["--lto=thin", "x"]) {
        case .err(let message): println(message); return 11;
        case .ok(let args): if !(args.value("lto") ?? "").equals("thin") { return 12; }
    }
    // Help and version do not require positionals.
    switch cli.parse(["--help"]) {
        case .err(let message): return 13;
        case .ok(let args): if !args.has("help") { return 14; }
    }
    println(error_of(Vec<String>.new()));
    println(error_of(["--outptu", "x"]));
    println(error_of(["--secre", "x"]));
    println(error_of(["-L", "9", "x"]));
    println(error_of(["-v", "-q", "x"]));
    println(error_of(["x", "-o"]));
    println(error_of(["x", "--verbose=yes"]));
    println(error_of(["x", "-o", ""]));
    println(error_of(["-z", "x"]));
    print(cli.help());
    0
}
