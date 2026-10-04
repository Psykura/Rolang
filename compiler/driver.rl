// Full native pipeline and external LLVM/C toolchain. LLVM is emitted here as
// text; clang owns target optimization, assembly, object emission and linking.
pub import "frontend.rl"
pub import "build_cache.rl"
import "codegen/backend.rl"
import "mir_dump.rl"
import "mir_print.rl"
import std.process
import std.io
import std.sha256
import std.fs
import std.path
import std.string_builder
import "module_abi.rl"

pub struct CompileOptions {
    pub var emit: String = "exe";
    pub var opt_level: i32 = 2;
    pub var output: String = "";
    pub var target: String = "";
    pub var runtime: String = "";
    pub var stdlib: String = "";
    pub var clang: String = "";
    pub var cc: String = "";
    pub var lto: String = "none";
    pub var linker: String = "";
    pub var cache_dir: String = "";
    pub var cache_context: String = "";
    pub var verbose: Bool = false;
    // -g: DWARF line tables and variables; on Darwin a .dSYM beside the executable.
    pub var debug_info: Bool = false;
    pub let include_roots: Vec<String>;
    pub static def new() -> CompileOptions {
        CompileOptions { emit: "exe", opt_level: 2, output: "", target: "", runtime: "", stdlib: "", clang: "", cc: "",
            lto: "none", linker: "", cache_dir: "", cache_context: "", verbose: false, include_roots: Vec<String>.new() }
    }
}
pub struct CompileResult {
    pub let success: Bool;
    pub let output: String;
    pub let cache_hit: Bool;
    // Errors and warnings; `sources` holds the text of every parsed file for rendering them.
    pub let diagnostics: Vec<Diagnostic>;
    pub let sources: Dict<String, String>;
}
pub def find_tool(name: String) -> String? {
    if name.contains("/") {
        let mode = fs_mode(name);
        if mode >= 0 && (mode & 73) > 0 { return path_resolve(absolute_path(name)); }
        return nil;
    }
    let search = env_get("PATH");
    for root in search.split(":") {
        var directory = root; if directory.len() == 0 { directory = "."; }
        let candidate = path_join(directory, name);
        let mode = fs_mode(candidate);
        if mode >= 0 && (mode & 73) > 0 { return path_resolve(absolute_path(candidate)); }
    }
    nil
}
pub def cleanup_build_dir(directory: String) -> Void {
    if let entries = dir_list(directory) { for name in entries { fs_remove(path_join(directory, name)); } }
    fs_remove(directory);
}
// LLVM emits either raw bitcode or the Darwin bitcode wrapper. Archive records
// are binary-safe, so both can use the existing native module object slot.
pub def is_llvm_bitcode(data: String) -> Bool {
    if data.len() < 4 { return false; }
    if data.byte_at(0) == 66 && data.byte_at(1) == 67 && data.byte_at(2) == 192 && data.byte_at(3) == 222 { return true; }
    data.byte_at(0) == 222 && data.byte_at(1) == 192 && data.byte_at(2) == 23 && data.byte_at(3) == 11
}
pub struct CompilationDriver {
    let options: CompileOptions;
    let diagnostics: Vec<Diagnostic>;
    var sources: Dict<String, String>;
    var temporary: String;
    var clang: String;
    var cc: String;
    var linker: String;
    let tool_watches: Dict<String, String>;
    pub static def new(options: CompileOptions) -> CompilationDriver {
        CompilationDriver { options, diagnostics: Vec<Diagnostic>.new(), sources: Dict<String, String>.new(), temporary: "", clang: "", cc: "", linker: "", tool_watches: Dict<String, String>.with_capacity(16, 1) }
    }
    def fail(message: String = "") -> CompileResult {
        if message.len() > 0 { self.error(message); }
        self.result(false, "", false)
    }
    def error(message: String) -> Void { self.diagnostics.push(Diagnostic.error(message)); }
    def result(success: Bool, output: String, cache_hit: Bool) -> CompileResult {
        CompileResult { success, output, cache_hit, diagnostics: self.diagnostics, sources: self.sources }
    }
    def discover_resources() -> Void {
        let options = self.options;
        if options.stdlib.len() == 0 { options.stdlib = env_get("ROLANG_STDLIB"); }
        let candidates = Vec<String>.new();
        if options.stdlib.len() > 0 { candidates.push(options.stdlib); }
        else {
            // Explicit -I roots take precedence, including their bundled std.
            for root in options.include_roots { if path_is_file(path_join(root, "std/range.rl")) { candidates.push(root); } }
            if let exe = executable_path() {
                let parent = path_dirname(exe);
                candidates.push(path_join(parent, "../lib/rolang"));
                candidates.push(path_join(parent, ".."));
            }
            candidates.push(".");
        }
        var standard = "";
        for candidate in candidates { if path_is_file(path_join(candidate, "std/range.rl")) { standard = path_resolve(candidate); break; } }
        if options.stdlib.len() > 0 && standard.len() == 0 { self.error("Standard library not found: " + options.stdlib); }
        if standard.len() > 0 {
            options.stdlib = standard; var present = false;
            for root in options.include_roots { if path_resolve(root).equals(standard) { present = true; } }
            if !present { options.include_roots.push(standard); }
        }
        if options.runtime.len() == 0 { options.runtime = env_get("ROLANG_RUNTIME"); }
        if options.runtime.len() == 0 && standard.len() > 0 { options.runtime = path_join(standard, "runtime/rolang_rt.c"); }
    }
    def command(args: Vec<String>, stage: String) -> Bool {
        if self.options.verbose {
            let command = StringBuilder.new();
            for arg in args { if command.len() > 0 { command.append(" "); } command.append(llvm_quote(arg)); }
            eprintln(stage + ": " + command.to_string());
        }
        let log = path_join(self.temporary, "tool.log");
        let status = run_argv_log(args, log);
        if status != 0 {
            var message = stage + f" failed (exit {status})";
            if let report = fs_read_text(log, 4194304) { if report.len() > 0 { message += ":\n" + report; } }
            self.error(message); return false;
        }
        if let report = fs_read_text(log, 4194304) { if report.len() > 0 { eprintln(report); } }
        true
    }
    def tool_args(tool: String) -> Vec<String> {
        let args = [tool];
        if self.options.target.len() > 0 { args.push("--target=" + self.options.target); }
        args
    }
    def watch_runtime_dependencies(text: String, frontend: Frontend) -> Bool {
        if !text.starts_with("runtime:") { return false; }
        let token = StringBuilder.new(); var index = 8;
        while index <= (text.len() as i32) {
            var ch = 32; if index < (text.len() as i32) { ch = text.byte_at(index); }
            if ch == 92 {
                index += 1; if index >= (text.len() as i32) { return false; }
                ch = text.byte_at(index);
                if ch != 10 && ch != 13 { token.append_byte(ch as u8); }
            } else if ch == 36 && index + 1 < (text.len() as i32) && text.byte_at(index+1) == 36 {
                token.append_byte(36 as u8); index += 1;
            } else if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
                let name = token.to_string();
                if name.len() > 0 {
                    let path = absolute_path(name);
                    if !frontend.input_watches.contains(path) { frontend.input_watches[path] = input_snapshot(path); }
                    token.clear();
                }
            } else { token.append_byte(ch as u8); }
            index += 1;
        }
        true
    }
    def cache(entry: String, output: String) -> BuildCache? {
        // Debug builds also produce a .dSYM, which the cache does not store.
        if self.options.debug_info { return nil; }
        if self.options.cache_dir.len() == 0 || !(self.options.emit.equals("exe") || self.options.emit.equals("obj") || self.options.emit.equals("module")) { return nil; }
        guard let compiler = executable_path() else { return nil; }
        guard let compiler_hash = file_sha256(compiler) else { return nil; }
        self.tool_watches[compiler] = compiler + "|file|" + compiler_hash;
        let context = ["rolang-cache-1", compiler_hash, entry, output, path_resolve("."),
            self.options.emit, self.options.opt_level.to_string(), self.options.target, self.options.cache_context,
            self.options.lto, self.linker];
        for root in self.options.include_roots { context.push(path_resolve(root)); }
        for variable in ["CC", "PATH", "ROLANG_CLANG", "ROLANG_RT_CFLAGS", "SDKROOT", "DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET",
            "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "LIBRARY_PATH", "COMPILER_PATH", "GCC_EXEC_PREFIX", "SOURCE_DATE_EPOCH", "ZERO_AR_DATE"] {
            context.push(variable);
            if let value = try_env_get(variable) { context.push("set"); context.push(value); }
            else { context.push("unset"); context.push(""); }
        }
        let tools = [self.clang]; if self.options.emit.equals("exe") { tools.push(self.cc); }
        let log = path_join(self.temporary, "tool.log");
        for tool in tools {
            guard let hash = file_sha256(tool) else { return nil; }
            context.push(tool); context.push(hash);
            self.tool_watches[tool] = tool + "|file|" + hash;
            if run_argv_log([tool, "--version"], log) != 0 { return nil; }
            guard let report = fs_read_text(log, 4194304) else { return nil; }
            context.push(report);
        }
        if run_argv_log([self.clang, "-dumpmachine"], log) != 0 { return nil; }
        guard let machine = fs_read_text(log, 4194304) else { return nil; }
        context.push(machine);
        if self.options.emit.equals("exe") {
            // LTO also depends on the linker and its bitcode reader. Clang's
            // queries respect its installation/configuration, including libLTO
            // on Darwin and the LLVMgold plugin used by GNU ld on ELF targets.
            if !self.options.lto.equals("none") || self.linker.len() > 0 {
                var linker = self.linker;
                if linker.len() == 0 {
                    if run_argv_log([self.cc, "-print-prog-name=ld"], log) != 0 { return nil; }
                    guard let requested = fs_read_text(log, 4194304) else { return nil; }
                    guard let found = find_tool(requested.trim()) else { return nil; }
                    linker = found;
                }
                context.push(linker); context.push(input_snapshot(linker));
                self.tool_watches[linker] = input_snapshot(linker);
                if !self.options.lto.equals("none") {
                    for library in ["libLTO.dylib", "LLVMgold.so"] {
                        if run_argv_log([self.cc, "-print-file-name=" + library], log) != 0 { return nil; }
                        guard let requested = fs_read_text(log, 4194304) else { return nil; }
                        let path = absolute_path(requested.trim()); let state = input_snapshot(path);
                        context.push(path); context.push(state); self.tool_watches[path] = state;
                    }
                }
            }
            guard let hash = file_sha256(self.options.runtime) else { return nil; }
            let runtime_path = absolute_path(self.options.runtime);
            context.push(runtime_path); context.push(path_resolve(runtime_path)); context.push(hash);
            self.tool_watches[runtime_path] = path_resolve(runtime_path) + "|file|" + hash;
            // Darwin SDK selection can change independently of compiler bytes.
            if let xcrun = find_tool("xcrun") {
                for flag in ["--show-sdk-path", "--show-sdk-version"] {
                    if run_argv_log([xcrun, flag], log) != 0 { return nil; }
                    guard let report = fs_read_text(log, 4194304) else { return nil; }
                    context.push(report);
                }
            }
        }
        BuildCache.new(absolute_path(self.options.cache_dir), context)
    }
    pub def compile_file(input: String) -> CompileResult {
        if !(self.options.lto.equals("none") || self.options.lto.equals("full") || self.options.lto.equals("thin")) {
            return self.fail("Unknown LTO mode: " + self.options.lto);
        }
        self.discover_resources(); if error_count(self.diagnostics) > 0 { return self.fail(); }
        let emit = self.options.emit; let entry = absolute_path(input);
        var output = self.options.output;
        let text_mode = emit.equals("llvm") || emit.equals("mir") || emit.equals("mir-opt") || emit.equals("llvm-opt") || emit.equals("asm");
        if output.len() == 0 && !text_mode {
            let extension = path_extension(entry);
            var suffix_size = extension.len(); if suffix_size > 0 { suffix_size += 1; }
            output = entry.substring(0, (entry.len() - suffix_size) as i32);
            if emit.equals("obj") { output += ".o"; }
            if emit.equals("module") { output += ".rlm"; }
        }
        if output.len() > 0 && !output.equals("-") { output = absolute_path(output); }
        if output.equals("-") && !text_mode { return self.fail("Binary output requires a file path"); }
        if !path_is_file(entry) { return self.fail("Input file not found: " + entry); }
        if output.len() > 0 && path_resolve(output).equals(path_resolve(entry)) { return self.fail("Output would overwrite the source file"); }
        if !text_mode || emit.equals("asm") || emit.equals("llvm-opt") {
            var requested = self.options.clang;
            if requested.len() == 0 { requested = env_get("ROLANG_CLANG"); }
            if requested.len() == 0 { requested = "clang"; }
            guard let tool = find_tool(requested) else { return self.fail("LLVM compiler not found: " + requested + "; use --clang or ROLANG_CLANG"); }
            self.clang = tool;
            if emit.equals("exe") {
                requested = self.options.cc; if requested.len() == 0 { requested = env_get("CC"); }
                if requested.len() == 0 { requested = self.clang; }
                guard let ctool = find_tool(requested) else { return self.fail("C compiler not found: " + requested); }
                self.cc = ctool;
                if self.options.linker.len() > 0 {
                    guard let linker = find_tool(self.options.linker) else { return self.fail("Linker not found: " + self.options.linker); }
                    self.linker = linker;
                }
                if !path_is_file(self.options.runtime) { return self.fail("Runtime not found: " + self.options.runtime + "; use --runtime or ROLANG_RUNTIME"); }
            }
        }
        var directory = env_get("TMPDIR"); if directory.len() == 0 { directory = "/tmp"; }
        if output.len() > 0 && !output.equals("-") {
            directory = path_dirname(output);
            if text_mode && !path_is_dir(directory) { return self.fail("Cannot write output file: directory does not exist: " + directory); }
            if !fs_mkdirs(directory) { return self.fail("Cannot create output directory: " + directory); }
        }
        guard let temp = fs_temp_dir(path_join(directory, ".rolang-XXXXXX")) else { return self.fail("Cannot create build temporary directory: " + directory); }
        self.temporary = temp;
        let result = self.compile_in_directory(entry, output);
        cleanup_build_dir(temp); self.temporary = ""; result
    }
    def compile_in_directory(entry: String, output: String) -> CompileResult {
        let emit = self.options.emit; let cache = self.cache(entry, output);
        if let storage = cache { if storage.restore(output) {
            if self.options.verbose { eprintln("Cached -> " + output); }
            return self.result(true, output, true);
        } }
        let frontend = Frontend.new(self.options.include_roots, self.options.cache_dir.len() > 0);
        if self.options.target.len() > 0 { frontend.module_target = self.options.target; }
        if emit.equals("module") { frontend.symbol_table.separate_modules = true; }
        frontend.debug_info = self.options.debug_info;
        frontend.load(entry); frontend.resolve_modules();
        var content = "";
        if emit.equals("mir") {
            if let mir = frontend.build_mir_modules() { content = format_mir(mir.program, mir.type_table); }
        } else {
            if let post = frontend.postprocess_mir(self.options.opt_level) {
                if emit.equals("mir-opt") { content = format_mir(post.program, post.type_table); }
                else {
                    var owner = "";
                    if frontend.symbol_table.separate_modules { owner = frontend.module_key(path_resolve(entry)); }
                    if emit.equals("module") { for func in post.program.functions {
                        if func.name.equals("main") { return self.fail("A library module cannot define main"); }
                    } }
                    let llvm = compile_to_llvm(post, frontend.arena, owner, self.options.debug_info);
                    // Code generation reports compiler defects, except for the release/trace hook ABI check.
                    for error in llvm.errors {
                        if error.contains(" has an invalid signature; ") { self.error(error); } else { self.error(internal_compiler_error(error)); }
                    }
                    content = llvm.text;
                    if self.options.target.len() > 0 { content = "target triple = " + llvm_quote(self.options.target) + "\n" + content; }
                }
            }
        }
        for diagnostic in frontend.diagnostics { self.diagnostics.push(diagnostic); }
        self.sources = frontend.sources();
        if error_count(self.diagnostics) > 0 || content.len() == 0 { return self.fail(); }
        for module in frontend.graph.get_all_modules() {
            if output.len() > 0 && path_resolve(output).equals(module.path) { return self.fail("Output would overwrite an imported source: " + module.path); }
        }
        for path in frontend.artifact_paths {
            if output.len() > 0 && path_resolve(output).equals(path_resolve(path)) { return self.fail("Output would overwrite an imported artifact: " + path); }
        }
        if emit.equals("module") {
            for module in frontend.graph.get_all_modules() {
                let key = frontend.module_key(module.path);
                if !module.path.equals(path_resolve(entry)) && key.starts_with("user:") && !frontend.module_objects.contains(key) {
                    return self.fail("Compile dependency as a native module first: " + module.path);
                }
            }
        }
        if emit.equals("llvm") || emit.equals("mir") || emit.equals("mir-opt") { return self.emit_text(content, output); }
        let ir = path_join(self.temporary, "input.ll"); let artifact = path_join(self.temporary, "artifact");
        if !fs_write_atomic(ir, content) { return self.fail("Cannot write temporary LLVM IR"); }
        let args = self.tool_args(self.clang);
        args.push("-Wno-override-module"); args.push("-O" + self.options.opt_level.to_string());
        if emit.equals("asm") { args.push("-S"); }
        else if emit.equals("llvm-opt") { args.push("-S"); args.push("-emit-llvm"); }
        else { args.push("-c"); }
        if emit.equals("exe") || emit.equals("obj") || emit.equals("module") {
            if self.options.lto.equals("none") { args.push("-fno-lto"); }
            else { args.push("-flto=" + self.options.lto); }
        }
        args.push(ir); args.push("-o");
        var object = artifact; if emit.equals("exe") || emit.equals("module") { object = path_join(self.temporary, "program.o"); }
        args.push(object);
        if !self.command(args, "LLVM compilation") { return self.fail(); }
        if !self.options.lto.equals("none") && (emit.equals("exe") || emit.equals("obj") || emit.equals("module")) {
            guard let data = fs_read_text(object, 134217728) else { return self.fail("Cannot read LTO object"); }
            if !is_llvm_bitcode(data) { return self.fail("LTO requires LLVM bitcode from --clang"); }
        }
        if emit.equals("asm") || emit.equals("llvm-opt") {
            guard let text = fs_read_text(artifact) else { return self.fail("Cannot read backend text output"); }
            return self.emit_text(text, output);
        }
        if emit.equals("exe") {
            let runtime_obj = path_join(self.temporary, "runtime.o");
            let compile = self.tool_args(self.cc); compile.push("-c"); compile.push(absolute_path(self.options.runtime));
            compile.push("-o"); compile.push(runtime_obj);
            var runtime_opt = 0; if self.options.opt_level >= 1 { runtime_opt = 3; }
            compile.push("-O" + runtime_opt.to_string()); compile.push("-DROLANG_SINGLE_THREADED"); compile.push("-DROLANG_THREADED");
            if self.options.debug_info { compile.push("-g"); }
            if runtime_opt >= 1 {
                // Mach-O has no symbol interposition to disable; clang warns about the flag there.
                var target = self.options.target; if target.len() == 0 { target = host_target(); }
                if !target.contains("apple") { compile.push("-fno-semantic-interposition"); }
                compile.push("-fvisibility=hidden");
            }
            if !self.options.lto.equals("none") { compile.push("-flto=" + self.options.lto); }
            // Runtime C flags use whitespace-separated arguments.
            for flag in env_get("ROLANG_RT_CFLAGS").replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ") {
                if flag.len() > 0 { compile.push(flag); }
            }
            if self.options.lto.equals("none") { compile.push("-fno-lto"); }
            if let storage = cache {
                let scan = Vec<String>.new(); let dependencies = path_join(self.temporary, "runtime.d");
                for arg in compile { if arg.equals(runtime_obj) { scan.push(dependencies); } else { scan.push(arg); } }
                scan.push("-MM"); scan.push("-MT"); scan.push("runtime");
                // Cache-only scans may fail without preventing ordinary builds.
                let log = path_join(self.temporary, "tool.log");
                if run_argv_log(scan, log) != 0 { frontend.cache_inputs_stable = false; }
                else if let data = fs_read_text(dependencies, 4194304) {
                    if !self.watch_runtime_dependencies(data, frontend) { frontend.cache_inputs_stable = false; }
                } else { frontend.cache_inputs_stable = false; }
            }
            if !self.command(compile, "Runtime compilation") { return self.fail(); }
            if !self.options.lto.equals("none") {
                guard let data = fs_read_text(runtime_obj, 134217728) else { return self.fail("Cannot read LTO runtime object"); }
                if !is_llvm_bitcode(data) { return self.fail("LTO requires LLVM bitcode from the C compiler; use --cc with a clang compatible with --clang"); }
            }
            let link = self.tool_args(self.cc); link.push(object); link.push(runtime_obj); link.push("-lm"); link.push("-o"); link.push(artifact);
            // std.tls loads OpenSSL with dlopen, which glibc before 2.34 keeps in libdl.
            var link_target = self.options.target; if link_target.len() == 0 { link_target = host_target(); }
            if link_target.contains("linux") { link.push("-ldl"); }
            link.push("-O" + self.options.opt_level.to_string());
            if self.options.lto.equals("none") { link.push("-fno-lto"); }
            else { link.push("-flto=" + self.options.lto); }
            if self.linker.len() > 0 { link.push("--ld-path=" + self.linker); }
            var index = 0; let emitted = Dict<String, Bool>.with_capacity(16, 1);
            for data in frontend.module_objects.values() {
                let hash = sha256(data); if emitted.contains(hash) { continue; } emitted[hash] = true;
                let dependency = path_join(self.temporary, f"dependency_{index}.o"); index += 1;
                if !fs_write_atomic(dependency, data) { return self.fail("Cannot extract native module object"); }
                if self.options.lto.equals("none") && is_llvm_bitcode(data) {
                    // --no-lto remains usable with distributed bitcode modules:
                    // compile each separately, then perform an ordinary link.
                    let native = path_join(self.temporary, f"dependency_native_{index}.o");
                    let materialize = self.tool_args(self.clang);
                    for arg in ["-Wno-override-module", "-O" + self.options.opt_level.to_string(), "-fno-lto", "-c", "-x", "ir", dependency, "-o", native] { materialize.push(arg); }
                    if !self.command(materialize, "Module bitcode compilation") { return self.fail(); }
                    link.push(native);
                } else { link.push(dependency); }
            }
            if !self.command(link, "Linking") { return self.fail(); }
            if self.options.debug_info && !self.debug_symbols(artifact, output) { return self.fail(); }
        }
        if emit.equals("module") {
            guard let data = fs_read_text(object, 134217728) else { return self.fail("Cannot read native module object"); }
            let sources = Dict<String, ModuleSource>.with_capacity(16, 1);
            for module in frontend.graph.get_all_modules() { if let source = module.source {
                sources[frontend.module_key(module.path)] = ModuleSource { text: source, imports: module.import_paths };
            } }
            let owner = frontend.module_key(path_resolve(entry)); frontend.module_objects[owner] = data;
            let archive = encode_module_artifact(ModuleArtifact { entry: owner, sources, objects: frontend.module_objects }, frontend.module_target, module_abi_version());
            if archive.len() > 134217728 { return self.fail("Native module archive exceeds 128 MiB"); }
            if !fs_write_atomic(artifact, archive) { return self.fail("Cannot write native module archive"); }
        }
        if !path_is_file(artifact) || !fs_move(artifact, output) { return self.fail("Cannot publish output: " + output); }
        if let storage = cache {
            for pair in self.tool_watches.entries() { frontend.input_watches[pair.key] = pair.value; }
            if frontend.cache_inputs_stable && frontend.diagnostics.len() == 0 { storage.store(output, frontend.input_watches); }
        }
        if self.options.verbose { eprintln("Compiled -> " + output); }
        self.result(true, output, false)
    }
    // Darwin keeps DWARF in the object files, which are temporary: collect it
    // into OUTPUT.dSYM, where lldb finds it next to the executable.
    def debug_symbols(artifact: String, output: String) -> Bool {
        var target = self.options.target; if target.len() == 0 { target = host_target(); }
        if !target.contains("apple") { return true; }
        var tool = path_join(path_dirname(self.clang), "dsymutil");
        if !path_is_file(tool) {
            guard let found = find_tool("dsymutil") else { self.error("dsymutil not found; it is needed for -g on Darwin"); return false; }
            tool = found;
        }
        self.command([tool, artifact, "-o", output + ".dSYM"], "Debug symbols")
    }
    def emit_text(content: String, output: String) -> CompileResult {
        if output.len() == 0 || output.equals("-") { print(content); }
        else if !fs_write_atomic(output, content) { return self.fail("Cannot write output: " + output); }
        self.result(true, output, false)
    }
}
