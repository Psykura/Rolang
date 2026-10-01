import "driver.rl"
import "mir_dump.rl"
import "codegen/backend.rl"
import std.process
import std.io
import std.fs
import std.path
import std.string_builder

def compiler_usage() -> Void {
    println("usage: rolangc [options] input.rl");
    println("  -o FILE                  output path (default: source without .rl)");
    println("  -c, --emit obj           emit an object file");
    println("  --emit module            export a native .rlm library");
    println("  --emit llvm|llvm-opt|asm|mir|mir-opt  text output (-o FILE or stdout)");
    println("  -O0|-O1|-O2|-O3          optimization level (default: O2)");
    println("  --lto[=full|thin] --no-lto  link-time optimization (default: none)");
    println("  -I ROOT                  source root (repeatable)");
    println("  --stdlib ROOT --runtime FILE  override bundled resources");
    println("  --clang FILE --cc FILE   LLVM and C toolchain commands");
    println("  --linker FILE            select the linker through clang");
    println("  --target TRIPLE          64-bit target triple");
    println("  --cache-dir DIR --no-cache  opt-in build cache");
    println("  -v, --verbose            build and cache diagnostics");
    println("  --parse|--resolve|--check|--hir|--mono|--mir|--mir-post|--llvm [--fields]  pass inspection");
}
def inspection_output(content: String, output: String) -> i32 {
    if output.len() == 0 || output.equals("-") { print(content); return 0; }
    if !fs_mkdirs(path_dirname(absolute_path(output))) || !fs_write_atomic(output, content) {
        eprintln("Cannot write output: " + output); return 1;
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

pub def run_compiler_cli() -> i32 {
    let options = CompileOptions.new();
    var mode = "";
    var input = "";
    let roots = options.include_roots;
    var index = 1;
    var opt_level = 2;
    var fields = false;
    var no_cache = false;
    var source_only = false;
    var emit_set = false;
    while index < argc() {
        let arg = argv(index);
        if source_only {
            if input.len() > 0 { eprintln("Only one input source is supported"); return 2; } input = arg;
        } else if arg.equals("--") { source_only = true; }
        else if arg.equals("--help") || arg.equals("-h") { compiler_usage(); return 0; }
        else if arg.equals("--version") { println("rolangc 0.1.0"); return 0; }
        else if arg.equals("--parse") || arg.equals("--resolve") || arg.equals("--check") || arg.equals("--hir") || arg.equals("--mono") || arg.equals("--mir") || arg.equals("--mir-post") || arg.equals("--llvm") {
            if mode.len() > 0 || emit_set { eprintln("Select one compiler output or inspection mode"); return 2; } mode = arg;
        }
        else if arg.equals("-O0") { opt_level = 0; }
        else if arg.equals("-O1") { opt_level = 1; }
        else if arg.equals("-O2") { opt_level = 2; }
        else if arg.equals("-O3") { opt_level = 3; }
        else if arg.equals("--lto") || arg.equals("--lto=full") { options.lto = "full"; }
        else if arg.equals("--lto=thin") { options.lto = "thin"; }
        else if arg.equals("--no-lto") || arg.equals("--lto=none") { options.lto = "none"; }
        else if arg.starts_with("--lto=") { eprintln("Unknown LTO mode: " + arg); return 2; }
        else if arg.equals("--fields") { fields = true; }
        else if arg.equals("-v") || arg.equals("--verbose") { options.verbose = true; }
        else if arg.equals("--no-cache") { no_cache = true; }
        else if arg.equals("--no-color") {}
        else if arg.equals("-c") || arg.equals("--compile-only") {
            if mode.len() > 0 || emit_set { eprintln("Select one compiler output or inspection mode"); return 2; }
            options.emit = "obj"; emit_set = true;
        }
        else if arg.equals("-I") || arg.equals("--include-path") || arg.equals("-o") || arg.equals("--output") || arg.equals("--emit") || arg.equals("--target") || arg.equals("--runtime") || arg.equals("--stdlib") || arg.equals("--clang") || arg.equals("--cc") || arg.equals("--linker") || arg.equals("--cache-dir") || arg.equals("--cache-context") {
            index += 1;
            if index >= argc() { eprintln(arg + " requires a value"); return 2; }
            let value = argv(index); if value.len() == 0 { eprintln(arg + " requires a nonempty value"); return 2; }
            if arg.equals("-I") || arg.equals("--include-path") { roots.push(value); }
            else if arg.equals("-o") || arg.equals("--output") { options.output = value; }
            else if arg.equals("--target") { options.target = value; }
            else if arg.equals("--runtime") { options.runtime = value; }
            else if arg.equals("--stdlib") { options.stdlib = value; }
            else if arg.equals("--clang") { options.clang = value; }
            else if arg.equals("--cc") { options.cc = value; }
            else if arg.equals("--linker") { options.linker = value; }
            else if arg.equals("--cache-dir") { options.cache_dir = value; }
            else if arg.equals("--cache-context") { options.cache_context = value; }
            else {
                if mode.len() > 0 || emit_set { eprintln("Select one compiler output or inspection mode"); return 2; }
                if !(value.equals("llvm") || value.equals("llvm-opt") || value.equals("asm") || value.equals("mir") || value.equals("mir-opt") || value.equals("obj") || value.equals("module")) {
                    eprintln("Unknown emit kind: " + value); return 2;
                }
                options.emit = value; emit_set = true;
            }
        } else if input.len() == 0 && !arg.starts_with("-") { input = arg; }
        else { eprintln("Unexpected argument: " + arg); return 2; }
        index += 1;
    }
    if input.len() == 0 { compiler_usage(); return 2; }
    options.opt_level = opt_level;
    if no_cache { options.cache_dir = ""; }
    if options.target.len() > 0 && !(options.target.starts_with("x86_64-") || options.target.starts_with("aarch64-") || options.target.starts_with("arm64-") || options.target.starts_with("riscv64-")) {
        eprintln("The native backend requires a supported 64-bit target triple"); return 2;
    }
    if fields && !(mode.equals("--mir") || mode.equals("--mir-post")) { eprintln("--fields requires --mir or --mir-post"); return 2; }
    if mode.len() == 0 {
        let result = CompilationDriver.new(options).compile_file(input);
        for error in result.errors { eprintln(error); }
        if result.success { return 0; } return 1;
    }
    if options.output.len() > 0 && !(mode.equals("--mir") || mode.equals("--mir-post") || mode.equals("--llvm")) { eprintln("-o requires a MIR or LLVM output mode"); return 2; }
    if options.stdlib.len() > 0 {
        if !path_is_file(path_join(options.stdlib, "std/range.rl")) { eprintln("Standard library not found: " + options.stdlib); return 1; }
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
    else if mode.equals("--mir-post") || mode.equals("--llvm") { frontend.postprocess_mir(opt_level); }
    for warning in frontend.warnings { eprintln("warning: " + warning); }
    if frontend.errors.len() > 0 {
        for error in frontend.errors { println(error); }
        return 1;
    }
    guard let module = root else { return 1; }
    guard let program = module.program else { return 1; }
    if options.output.len() > 0 && !options.output.equals("-") {
        for dependency in frontend.graph.get_all_modules() {
            if path_resolve(absolute_path(options.output)).equals(dependency.path) { eprintln("Output would overwrite an input source"); return 1; }
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
        if llvm.has_errors() { for error in llvm.errors { println(error); } return 1; }
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
