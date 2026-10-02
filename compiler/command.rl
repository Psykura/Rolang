import "driver.rl"
import "mir_dump.rl"
import "codegen/backend.rl"
import std.process
import std.io
import std.fs
import std.path
import std.string_builder
import std.cli

def inspection_output(content: String, output: String) -> i32 {
    if output.len() == 0 || output.equals("-") { print(content); return 0; }
    if !fs_mkdirs(path_dirname(absolute_path(output))) || !fs_write_atomic(output, content) {
        eprintln("rolangc: cannot write output: " + output); return 1;
    }
    0
}

def dump_hir(arena: HirArena, program: HirId, types: TypeTable) -> Void {
    for id in arena.preorder(program) { if let node = arena.get(id) {
        var text = node.form.kind();
        switch node.form {
            case .function(let data): text += "|" + data.name;
            case .struct_type(let data): text += "|" + data.name;
            case .enum_type(let data): text += "|" + data.name;
            default: if let type = node.form.type_id() { text += "|" + types.format_type(type); }
        }
        println(text);
    } }
}

def format_mir_kinds(program: MirProgram) -> String {
    let out = StringBuilder.new();
    for function in program.functions {
        out.append_line("FUNCTION|" + function.name);
        for id in function.block_order { if let block = function.get_block(id) {
            out.append_line(f"BLOCK|{id.id}");
            for op in block.ops { out.append_line("OP|" + op.kind()); }
            if let term = block.terminator { out.append_line("TERM|" + term.kind()); }
        } }
    }
    for func in program.externs { out.append_line("EXTERN|" + func.name); }
    out.to_string()
}

def command_line() -> CommandLine {
    let cli = CommandLine.new("rolangc", "[options] input.rl");
    cli.about = "Compiles a Rolang program and its imports to an executable.";
    cli.version = "rolangc 0.4.1";
    cli.positional("input.rl", "the program's main source file");
    cli.option("output", "FILE", "output path (default: the input without .rl)").short("o");
    let emit = cli.option("emit", "KIND", "output kind").choices(["exe", "obj", "module", "llvm", "llvm-opt", "asm", "mir", "mir-opt"]);
    emit.preset(["-c", "--compile-only"], "obj", "emit an object file (--emit obj)");
    cli.option("opt-level", "N", "optimization level (default: 2)").short("O").choices(["0", "1", "2", "3"]);
    cli.option("lto", "MODE", "link-time optimization (default: none)").choices(["full", "thin", "none"]).implicit("full").preset(["--no-lto"], "none");
    cli.option("include-path", "ROOT", "add a source root").short("I");
    cli.option("stdlib", "ROOT", "use the standard library under ROOT");
    cli.option("runtime", "FILE", "use this runtime C source");
    cli.option("clang", "FILE", "LLVM compiler");
    cli.option("cc", "FILE", "C compiler for the runtime");
    cli.option("linker", "FILE", "linker, selected through clang");
    cli.option("target", "TRIPLE", "64-bit target triple");
    cli.option("cache-dir", "DIR", "reuse build outputs from DIR");
    cli.flag("no-cache", "disable the build cache");
    cli.option("cache-context", "TEXT", "extra build cache key").hide();
    cli.option("color", "WHEN", "colored diagnostics (default: auto)").choices(["auto", "always", "never"]).implicit("always").preset(["--no-color"], "never");
    cli.flag("verbose", "print build commands and cache decisions").short("v");
    let passes = ["parse", "resolve", "check", "hir", "mono", "mir", "mir-post", "llvm"];
    let inspect = cli.option("inspect", "PASS", "print a pass and stop; --PASS is short for this").choices(passes);
    for pass in passes { inspect.preset(["--" + pass], pass); }
    cli.flag("fields", "with --mir or --mir-post, print MIR fields");
    cli.exclusive(["inspect", "emit"]);
    cli
}

// Colors follow --color; `auto` colors a terminal unless NO_COLOR is set or TERM is dumb.
def use_color(args: CliArgs) -> Bool {
    let when = args.value("color") ?? "auto";
    if when.equals("always") { return true; }
    if when.equals("never") { return false; }
    stderr_is_terminal() && env_get("NO_COLOR").len() == 0 && !env_get("TERM").equals("dumb")
}

def report(diagnostics: Vec<Diagnostic>, sources: Dict<String, String>, color: Bool) -> Void {
    if diagnostics.len() == 0 { return; }
    let renderer = DiagnosticRenderer.new(color, sources);
    for diagnostic in sorted_diagnostics(diagnostics) { eprintln(renderer.render(diagnostic)); eprintln(""); }
    eprintln(renderer.summary(diagnostics));
}

pub def run_compiler_cli() -> i32 {
    let cli = command_line();
    guard let args = cli.parse_process() else { return cli.status; }
    let color = use_color(args);
    let options = CompileOptions.new();
    let roots = options.include_roots;
    for root in args.values("include-path") { roots.push(root); }
    let input = args.value("input.rl") ?? "";
    options.output = args.value("output") ?? "";
    options.emit = args.value("emit") ?? "exe";
    options.opt_level = (args.value("opt-level") ?? "2").to_i32();
    options.lto = args.value("lto") ?? "none";
    options.target = args.value("target") ?? "";
    options.runtime = args.value("runtime") ?? "";
    options.stdlib = args.value("stdlib") ?? "";
    options.clang = args.value("clang") ?? "";
    options.cc = args.value("cc") ?? "";
    options.linker = args.value("linker") ?? "";
    options.cache_dir = args.value("cache-dir") ?? "";
    options.cache_context = args.value("cache-context") ?? "";
    options.verbose = args.has("verbose");
    if args.has("no-cache") { options.cache_dir = ""; }
    var mode = "";
    if let pass = args.value("inspect") { mode = "--" + pass; }
    if options.target.len() > 0 && !(options.target.starts_with("x86_64-") || options.target.starts_with("aarch64-") || options.target.starts_with("arm64-") || options.target.starts_with("riscv64-")) {
        eprintln("rolangc: the native backend requires a supported 64-bit target triple"); return 2;
    }
    let fields = args.has("fields");
    if fields && !(mode.equals("--mir") || mode.equals("--mir-post")) { eprintln("rolangc: --fields requires --mir or --mir-post"); return 2; }
    if mode.len() == 0 {
        let result = CompilationDriver.new(options).compile_file(input);
        report(result.diagnostics, result.sources, color);
        if result.success { return 0; } return 1;
    }
    if options.output.len() > 0 && !(mode.equals("--mir") || mode.equals("--mir-post") || mode.equals("--llvm")) { eprintln("rolangc: -o requires --mir, --mir-post or --llvm"); return 2; }
    if options.stdlib.len() > 0 {
        if !path_is_file(path_join(options.stdlib, "std/range.rl")) { eprintln("rolangc: standard library not found: " + options.stdlib); return 1; }
        roots.push(options.stdlib);
    }
    let frontend = Frontend.new(roots);
    if options.target.len() > 0 { frontend.module_target = options.target; }
    var root: Module? = nil;
    if mode.equals("--parse") { root = frontend.parse_file(input); }
    else { root = frontend.load(input); frontend.resolve_modules(); }
    if mode.equals("--check") { frontend.check_modules(); }
    else if mode.equals("--hir") { frontend.build_hir_modules(); }
    else if mode.equals("--mono") { frontend.monomorphize_modules(); }
    else if mode.equals("--mir") { frontend.build_mir_modules(); }
    else if mode.equals("--mir-post") || mode.equals("--llvm") { frontend.postprocess_mir(options.opt_level); }
    report(frontend.diagnostics, frontend.sources(), color);
    if frontend.has_errors() { return 1; }
    guard let module = root else { return 1; }
    guard let program = module.program else { return 1; }
    if options.output.len() > 0 && !options.output.equals("-") {
        for dependency in frontend.graph.get_all_modules() {
            if path_resolve(absolute_path(options.output)).equals(dependency.path) { eprintln("rolangc: output would overwrite an input source"); return 1; }
        }
    }
    if mode.equals("--parse") {
        for id in frontend.arena.preorder(program) {
            if let node = frontend.arena.get(id) { println(node.form.kind()); }
        }
    } else if mode.equals("--check") {
        println("Type checking passed");
    } else if mode.equals("--hir") {
        guard let result = frontend.hir_result else { return 1; }
        dump_hir(result.arena, result.program, result.type_table);
    } else if mode.equals("--mono") {
        guard let result = frontend.mono_result else { return 1; }
        dump_hir(result.arena, result.program, result.type_table);
    } else if mode.equals("--mir") {
        guard let result = frontend.mir_result else { return 1; }
        var text = ""; if fields { text = format_mir_fields(result.program, result.type_table); } else { text = format_mir_kinds(result.program); }
        return inspection_output(text, options.output);
    } else if mode.equals("--llvm") {
        guard let result = frontend.post_result else { return 1; }
        var owner = ""; if frontend.symbol_table.separate_modules { owner = frontend.module_key(module.path); }
        let llvm = compile_to_llvm(result, frontend.arena, owner);
        if llvm.has_errors() {
            let errors = Vec<Diagnostic>.new();
            for error in llvm.errors { errors.push(Diagnostic.error(error)); }
            report(errors, frontend.sources(), color);
            return 1;
        }
        var text = llvm.text;
        if options.target.len() > 0 { text = "target triple = " + llvm_quote(options.target) + "\n" + text; }
        return inspection_output(text, options.output);
    } else if mode.equals("--mir-post") {
        guard let result = frontend.post_result else { return 1; }
        var text = ""; if fields { text = format_mir_fields(result.program, result.type_table); } else { text = format_mir_kinds(result.program); }
        return inspection_output(text, options.output);
    } else {
        let order = frontend.graph.get_compilation_order();
        for module in order.modules {
            println("MODULE|" + module.path);
            for export in module.exports.values() { println(f"EXPORT|{export.name}|{export.kind}|{export.visibility}|{export.symbol_id.id}"); }
        }
    }
    return 0;
}
