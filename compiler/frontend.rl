// Executable source-loading, parsing and name-resolution pipeline. Later passes
// consume this arena and its canonical symbol identities without reparsing.
pub import "parser.rl"
pub import "diagnostics.rl"
pub import "resolver.rl"
pub import "checker.rl"
pub import "monomorphize.rl"
pub import "mir_builder.rl"
pub import "mir_outparam_init.rl"
pub import "arc_insertion.rl"
pub import "async_lowering.rl"
pub import "mir_optimize.rl"
pub import "arc_optimization.rl"
import std.fs
import std.path
import std.collections
import "build_cache.rl"
import std.sha256
pub import "module_artifact.rl"
import "module_abi.rl"
import std.process

def label_of(import: ImportDeclAst) -> String {
    if import.module.len() > 0 { return join_strings(import.module, "."); }
    import.path
}

pub struct Frontend {
    pub let arena: AstArena;
    pub let graph: ModuleGraph;
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let resolutions: Dict<String, ResolutionResult>;
    pub let diagnostics: Vec<Diagnostic>;
    pub let input_watches: Dict<String, String>;
    pub var cache_inputs_stable: Bool;
    let track_inputs: Bool;
    pub var checked_program: NodeId?;
    pub var type_result: TypeCheckResult?;
    pub var hir_result: HirBuildResult?;
    pub var mono_result: MonomorphizationResult?;
    pub var mir_result: MirBuildResult?;
    pub var post_result: MirPostResult?;
    var post_opt_level: i32;
    let import_targets: Dict<i32, String>;
    let stdlib_path: String?;
    pub let module_sources: Dict<String, ModuleSource>;
    pub let module_objects: Dict<String, String>;
    pub let artifact_paths: Vec<String>;
    let implicit_imports: Dict<i32, String>;
    pub var module_target: String;
    let failed_sources: Dict<String, String>;
    var resolution_errors: i32;
    // -g: MIR carries statement positions for debug information.
    pub var debug_info: Bool;
    pub static def new(include_roots: Vec<String> = Vec<String>.new(), track_inputs: Bool = false) -> Frontend {
        let graph = ModuleGraph.new();
        var stdlib_path: String? = nil;
        for root in include_roots {
            let canonical = path_resolve(root);
            graph.source_roots.push(canonical);
            let bundled = path_join(canonical, "std");
            if path_is_file(path_join(bundled, "range.rl")) { stdlib_path = path_resolve(bundled); }
        }
        if let standard = stdlib_path { graph.source_roots.push(standard); }
        Frontend { arena: AstArena.new(true), graph, symbol_table: SymbolTable.new(),
            node_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            resolutions: Dict<String, ResolutionResult>.with_capacity(16, 1), diagnostics: Vec<Diagnostic>.new(),
            input_watches: Dict<String, String>.with_capacity(16, 1), track_inputs,
            cache_inputs_stable: true,
            checked_program: nil, type_result: nil, hir_result: nil, mono_result: nil, mir_result: nil, post_result: nil, post_opt_level: -1,
            import_targets: Dict<i32, String>.with_capacity(16, 0), stdlib_path,
            module_sources: Dict<String, ModuleSource>.with_capacity(16, 1), module_objects: Dict<String, String>.with_capacity(16, 1),
            artifact_paths: Vec<String>.new(), implicit_imports: Dict<i32, String>.with_capacity(16, 0), module_target: host_target(), failed_sources: Dict<String, String>.new(), resolution_errors: 0, debug_info: false }
    }
    pub def has_errors() -> Bool { error_count(self.diagnostics) > 0 }
    def error(message: String, file: String? = nil, span: Span? = nil) -> Void {
        self.diagnostics.push(Diagnostic.error(message, file, span));
    }
    def warning(message: String, file: String? = nil, span: Span? = nil) -> Void {
        self.diagnostics.push(Diagnostic.warning(message, file, span));
    }
    // Source text by path for every parsed module, for rendering diagnostics.
    pub def sources() -> Dict<String, String> {
        let sources = Dict<String, String>.new();
        for pair in self.failed_sources.entries() { sources[pair.key] = pair.value; }
        for module in self.graph.get_all_modules() { if let source = module.source { sources[module.path] = source; } }
        sources
    }
    pub def module_key(path: String) -> String {
        if let standard = self.stdlib_path { if path.starts_with(standard + "/") {
            return "std:" + path.substring((standard.len() + 1) as i32, (path.len() - standard.len() - 1) as i32);
        } }
        "user:" + path
    }
    def module_path(key: String) -> String {
        if key.starts_with("std:") {
            if let standard = self.stdlib_path { return path_join(standard, key.substring(4, (key.len()-4) as i32)); }
            return "/__rolang_std__/" + key.substring(4, (key.len()-4) as i32);
        }
        key.substring(5, (key.len()-5) as i32)
    }
    def import_key(id: NodeId, import: ImportDeclAst) -> String {
        if let implicit = self.implicit_imports[id.id] { return "core:" + implicit; }
        if import.module.len() > 0 { return encode_records(["module", join_strings(import.module, ".")]); }
        encode_records(["path", import.path])
    }
    def load_artifact(path: String) -> String? {
        self.watch_input(path); let parsed = read_module_artifact(path, self.module_target, module_abi_version());
        guard let artifact = parsed.artifact else { self.error("Cannot import module: " + parsed.error, path); return nil; }
        if self.track_inputs {
            let expected = path_resolve(path) + "|file|" + parsed.input_hash;
            if !(self.input_watches[absolute_path(path)] ?? "").equals(expected) { self.cache_inputs_stable = false; }
        }
        // Validate every conflict before mutating the shared source/object sets.
        for pair in artifact.sources.entries() {
            if let loaded = self.graph.get_module(self.module_path(pair.key)) {
                if let source = loaded.source { if !source.equals(pair.value.text) { self.error("Conflicting module source for " + pair.key, path); return nil; } }
            }
            if let previous = self.module_sources[pair.key] {
                var matches = previous.text.equals(pair.value.text) && previous.imports.len() == pair.value.imports.len();
                for imported in previous.imports.entries() { if !(pair.value.imports[imported.key] ?? "").equals(imported.value) { matches = false; } }
                if !matches { self.error("Conflicting module versions for " + pair.key, path); return nil; }
            }
        }
        for pair in artifact.objects.entries() { if let previous = self.module_objects[pair.key] {
            if !previous.equals(pair.value) { self.error("Conflicting native module objects for " + pair.key, path); return nil; }
        } }
        for pair in artifact.sources.entries() { self.module_sources[pair.key] = pair.value; }
        for pair in artifact.objects.entries() { self.module_objects[pair.key] = pair.value; }
        self.artifact_paths.push(path); self.symbol_table.separate_modules = true;
        self.module_path(artifact.entry)
    }
    pub def parse_file(path: String) -> Module? {
        var canonical = path_resolve(path);
        var saved = self.module_sources[self.module_key(path)];
        if let record = saved { canonical = path; }
        else { saved = self.module_sources[self.module_key(canonical)]; }
        if let module = self.graph.get_module(canonical) { return module; }
        var content: String? = nil;
        if let record = saved { content = record.text; }
        else { self.watch_input(path); content = fs_read_text(canonical); }
        guard let source = content else {
            var message = "cannot read input"; if !path_is_file(canonical) { message = "cannot open input"; }
            self.error(message, canonical); return nil;
        }
        if self.track_inputs && !self.module_sources.contains(self.module_key(canonical)) {
            let expected = canonical + "|file|" + sha256(source);
            let name = absolute_path(path);
            if !(self.input_watches[name] ?? "").equals(expected) { self.cache_inputs_stable = false; }
        }
        let parsed = parse_program_text(source, self.arena);
        for problem in parsed.errors { self.diagnostics.push(Diagnostic.error(problem.message, canonical, problem.span)); }
        // Keep the source so diagnostics can show it.
        if parsed.errors.len() > 0 { self.failed_sources[canonical] = source; return nil; }
        guard let program = parsed.program else { return nil; }
        let module = Module.new(canonical, canonical);
        module.source = source; module.program = program; module.state = ModuleState.parsed();
        self.arena.set_source_module(program, canonical);
        mark_module_declarations(self.arena, program, self.symbol_table, self.module_key(canonical), source);
        self.graph.add_module(module);
        module
    }
    def watch_input(path: String) -> Void {
        if self.track_inputs {
            let name = absolute_path(path);
            if !self.input_watches.contains(name) { self.input_watches[name] = input_snapshot(name); }
        }
    }
    def import_path(importer: Module, import: ImportDeclAst) -> String? {
        var relative = import.path;
        if import.module.len() > 0 { relative = join_strings(import.module, "/") + ".rl"; }
        // Dotted imports also search next to the importing source.
        {
            let local = path_join(path_dirname(importer.path), relative);
            self.watch_input(local);
            if path_is_file(local) { return path_resolve(local); }
        }
        for root in self.graph.source_roots {
            let candidate = path_join(root, relative);
            self.watch_input(candidate);
            if path_is_file(candidate) { return path_resolve(candidate); }
        }
        if import.module.len() > 1 && import.module[0].equals("std") {
            if let standard = self.stdlib_path {
                let candidate = path_join(standard, relative.substring(4, (relative.len()-4) as i32));
                self.watch_input(candidate);
                if path_is_file(candidate) { return path_resolve(candidate); }
            }
        }
        nil
    }
    def inject_core_imports(module: Module) -> Void {
        guard let standard = self.stdlib_path else { return; }
        if module.path.starts_with(standard + "/") { return; }
        guard let program = module.program else { return; }
        guard let node = self.arena.get(program) else { return; }
        switch node.form {
            case .program(let data):
                let existing = Dict<String, Bool>.with_capacity(16, 1);
                for id in data.items {
                    if let item = self.arena.get(id) {
                        switch item.form { case .import_decl(let import): existing[import.path] = true; default: {} }
                    }
                }
                let items = Vec<NodeId>.new();
                for name in ["vec.rl", "dict.rl", "string.rl", "range.rl", "cell.rl"] {
                    if !existing.contains(name) {
                        let implicit = self.arena.add(NodeForm.import_decl(ImportDeclAst {
                            visibility: "internal", path: path_join(standard, name), module: Vec<String>.new(), alias: nil
                        }));
                        self.implicit_imports[implicit.id] = name; items.push(implicit);
                    }
                }
                for id in data.items { items.push(id); }
                self.arena.replace(program, NodeForm.program(ProgramAst { items }));
                self.arena.set_source_module(program, module.path);
            default: {}
        }
    }
    pub def load(path: String) -> Module? {
        guard let root = self.parse_file(path) else { return nil; }
        // An iterative work list handles cycles and shared dependencies without
        // recursive loading or allocating duplicate ASTs for one source path.
        let pending = [root];
        var head = 0;
        while head < pending.len() {
            let module = pending[head]; head += 1;
            self.inject_core_imports(module);
            guard let program = module.program else { continue; }
            guard let node = self.arena.get(program) else { continue; }
            switch node.form {
                case .program(let data):
                    let seen = Dict<String, Bool>.with_capacity(16, 1);
                    for id in data.items {
                        guard let item = self.arena.get(id) else { continue; }
                        switch item.form {
                            case .import_decl(let import):
                                let implicit = self.implicit_imports.contains(id.id);
                                if !implicit {
                                    if import.path.len() == 0 && import.module.len() == 0 { self.error("Empty import path", module.path, item.span); continue; }
                                    var label = import.path; if import.module.len() > 0 { label = join_strings(import.module, "."); }
                                    if seen.contains(label) { self.warning("Duplicate import of '" + label + "'", module.path, item.span); }
                                    seen[label] = true;
                                    if import.module.len() == 0 {
                                        if !import.path.ends_with(".rl") && !import.path.ends_with(".rlm") { self.warning("Imported file '" + import.path + "' does not end in '.rl' or '.rlm'", module.path, item.span); }
                                        if import.path.starts_with("/") { self.warning("Imported absolute path '" + import.path + "'; consider a relative path or an -I include root", module.path, item.span); }
                                    }
                                }
                                let key = self.import_key(id, import); var target: String? = nil;
                                if let saved = self.module_sources[self.module_key(module.path)] {
                                    if let preserved = saved.imports[key] { target = self.module_path(preserved); }
                                    else { self.error("Cannot import module: missing preserved dependency", module.path, item.span); continue; }
                                } else { target = self.import_path(module, import); }
                                if let candidate = target {
                                    var canonical = candidate;
                                    if canonical.equals(module.path) { self.error("File '" + path_basename(module.path) + "' imports itself", module.path, item.span); continue; }
                                    if !implicit && import.path.len() > 0 {
                                        if let standard = self.stdlib_path {
                                            let bundled = path_join(standard, import.path);
                                            self.watch_input(bundled);
                                            if path_is_file(bundled) && !path_resolve(bundled).equals(canonical) { self.warning("Imported file '" + import.path + "' shadows the bundled standard library file at '" + bundled + "'", module.path, item.span); }
                                        }
                                    }
                                    if path_extension(canonical).equals("rlm") {
                                        guard let imported = self.load_artifact(canonical) else { continue; }
                                        canonical = imported;
                                    }
                                    let known = self.graph.has_module(canonical);
                                    if let dependency = self.parse_file(canonical) {
                                        self.graph.add_dependency(module.name, dependency.name);
                                        self.import_targets[id.id] = dependency.name;
                                        module.import_paths[key] = self.module_key(dependency.path);
                                        if !known { pending.push(dependency); }
                                    }
                                } else { self.error(f"Module not found: '{label_of(import)}'", module.path, item.span); }
                            default: {}
                        }
                    }
                default: {}
            }
        }
        root
    }
    pub def resolve_modules() -> Void {
        if self.has_errors() { return; }
        let order = self.graph.get_compilation_order();
        if let error = order.error { self.error(error); return; }
        for module in order.modules {
            guard let program = module.program else { continue; }
            let result = NameResolver.new(self.arena, self.symbol_table, self.node_symbols,
                self.graph, module, self.import_targets).resolve(program);
            self.resolutions[module.name] = result;
            module.symbol_table = self.symbol_table;
            for error in result.errors { self.diagnostics.push(Diagnostic.error(error.message, module.path, error.span)); self.resolution_errors += 1; }
            self.publish_exports(module, program, result);
            module.state = ModuleState.resolved();
            if result.errors.len() > 0 { module.state = ModuleState.error(); }
        }
    }
    pub def check_modules() -> TypeCheckResult? {
        if let cached = self.type_result { return cached; }
        // Name resolution errors leave error types behind; checking still reports
        // the program's other errors in the same run.
        if error_count(self.diagnostics) > self.resolution_errors { return nil; }
        let order = self.graph.get_compilation_order();
        if let error = order.error { self.error(error); return nil; }
        let earlier = Vec<ResolutionError>.new();
        for pair in self.resolutions.entries() { for error in pair.value.errors { earlier.push(error); } }
        let merged = ResolutionResult.new(self.symbol_table, self.node_symbols, earlier);
        let items = Vec<NodeId>.new();
        for module in order.modules {
            if let program = module.program { if let node = self.arena.get(program) {
                switch node.form { case .program(let data):
                    for item in data.items { if let child = self.arena.get(item) { switch child.form { case .import_decl: {} default: items.push(item); } } }
                    default: {}
                }
            } }
            if let resolution = self.resolutions[module.name] {
                for pair in resolution.imported_symbols.entries() { merged.imported_symbols[pair.key] = pair.value; }
                for pair in resolution.self_symbols.entries() { merged.self_symbols[pair.key] = pair.value; }
                for method in resolution.extension_methods { merged.extension_methods.push(method); }
                for pair in resolution.imported_extension_methods.entries() {
                    let methods = merged.imported_extension_methods[pair.key] ?? Vec<ImportedMethod>.new();
                    for method in pair.value { methods.push(method); }
                    merged.imported_extension_methods[pair.key] = methods;
                }
            }
        }
        let program = self.arena.add(NodeForm.program(ProgramAst { items }));
        let result = TypeChecker.new(self.arena, merged).check(program);
        self.checked_program = program; self.type_result = result;
        for error in result.errors { self.diagnostics.push(Diagnostic.error(error.message, error.file, error.span)); }
        for module in order.modules { if result.has_errors() { module.state = ModuleState.error(); } else { module.state = ModuleState.typechecked(); } }
        result
    }
    pub def build_hir_modules() -> HirBuildResult? {
        if let cached = self.hir_result { return cached; }
        guard let types = self.check_modules() else { return nil; }
        if self.has_errors() { return nil; }
        guard let program = self.checked_program else { return nil; }
        let result = HirBuilder.new(self.arena, types, self.symbol_table, self.node_symbols).build(program);
        self.hir_result = result;
        for error in result.errors { self.error(error); }
        result
    }
    pub def monomorphize_modules() -> MonomorphizationResult? {
        if let cached = self.mono_result { return cached; }
        guard let hir = self.build_hir_modules() else { return nil; }
        if self.has_errors() { return nil; }
        let result = Monomorphizer.new(hir).run(); self.mono_result = result;
        for error in result.errors { self.error(error); }
        result
    }
    pub def build_mir_modules() -> MirBuildResult? {
        if let cached = self.mir_result { return cached; }
        guard let mono = self.monomorphize_modules() else { return nil; }
        if self.has_errors() { return nil; }
        let result = MirBuilder.new(mono, self.debug_info).build();
        if !result.has_errors() { elide_outparam_default_init(result.program, result.type_table); }
        self.mir_result = result;
        for error in result.errors { self.error(error); }
        result
    }
    pub def postprocess_mir(opt_level: i32 = 2) -> MirPostResult? {
        if let cached = self.post_result { if self.post_opt_level == opt_level { return cached; } }
        guard let mir = self.build_mir_modules() else { return nil; }
        if self.has_errors() { return nil; }
        let copy = MirBuildResult { program: copy_mir_program(mir.program), type_table: mir.type_table, symbol_table: mir.symbol_table, errors: Vec<String>.new() };
        let result = lower_async(copy);
        if !result.has_errors() {
            if opt_level >= 2 { optimize_mir(result.program, result.type_table); }
            for error in insert_arc(result.program, result.type_table) { result.errors.push(error); }
            if opt_level >= 1 { optimize_arc_program(result.program, result.type_table); }
            for error in validate_mir_program(result.program) { result.errors.push(error); }
        }
        self.post_result = result; self.post_opt_level = opt_level; for error in result.errors { self.error(error); } result
    }
    def publish_exports(module: Module, program: NodeId, result: ResolutionResult) -> Void {
        guard let node = self.arena.get(program) else { return; }
        switch node.form {
            case .program(let data):
                for id in data.items {
                    if let sid = result.node_symbols[id.id] {
                        if let symbol = self.symbol_table.get_symbol(sid) {
                            var kind = "";
                            switch symbol.kind {
                                case .struct_type: kind = "struct"; case .enum_type: kind = "enum";
                                case .protocol: kind = "protocol"; case .type_alias: kind = "typealias";
                                case .function: kind = "function"; case .extern_func: kind = "externfunc";
                                case .variable: if let decl = symbol.decl_node { if let item = self.arena.get(decl) { switch item.form { case .constant_decl: kind = "constant"; default: {} } } }
                                default: {}
                            }
                            if kind.len() > 0 { module.add_export(symbol.name, sid, kind, symbol.visibility); }
                        }
                    }
                }
            default: {}
        }
        for export in result.re_exports { module.add_export(export.name, export.symbol_id, export.kind, "pub"); }
        for export in result.extension_methods { module.extension_exports.push(export); }
        for export in result.re_exported_extension_methods { module.extension_exports.push(export); }
    }
}
