// Full-compiler MIR -> LLVM IR text. No llvmlite or compiler subprocess is
// involved in producing the artifact; the caller owns assembly and linking.
pub import "types.rl"
pub import "../async_lowering.rl"
import "../conformance.rl"
import "../monomorphize.rl"
import std.string_builder
import std.path
import "../module_abi.rl"
import std.sha256
import "../acyclic.rl"
import "runtime.rl"
import "../mir_utils.rl"

pub struct LlvmResult {
    pub let text: String;
    pub let errors: Vec<String>;
    // With partitions: modules to compile separately and link together (text is the first).
    pub let modules: Vec<String>;
    pub def has_errors() -> Bool { self.errors.len() > 0 }
}
struct LlvmFieldDescriptor { let offset: i64; let type_id: i64; let tag: i32; }
struct LlvmModuleEmitter {
    let result: MirPostResult;
    let cache: LlvmTypeCache;
    let signatures: Dict<String, LlvmSignature>;
    let signature_order: Vec<String>;
    let function_names: Vec<String>;
    let symbol_names: Dict<i32, String>;
    let source_names: Dict<String, String>;
    let witness_names: Dict<String, String>;
    let globals: StringBuilder;
    let bodies: StringBuilder;
    let errors: Vec<String>;
    let owner: String;
    let linkages: Dict<String, String>;
    var string_id: i32;
    var arc_helpers: Bool;
    var alloc_helpers: Bool;
    var char_helpers: Bool;
    var frem_helpers: Bool;
    var collection_metadata: Bool;
    // Debug information (-g): metadata lines, numbered from !16 above the TBAA nodes.
    var debug: Bool;
    let debug_lines: StringBuilder;
    var next_meta: i32;
    let debug_files: Dict<String, i32>;
    let debug_types: Dict<i32, i32>;
    var debug_unit: i32;
    var debug_signature: i32;
    var debug_declare: Bool;
    // Partitioned output: the most modules to emit, the function text each
    // needs at least, and where each body sits in `bodies` (kind 0 inline
    // helper copied into every module, 1 function, 2 first module only).
    var partitions: i32;
    var partition_bytes: i64;
    let chunk_starts: Vec<i64>;
    let chunk_ends: Vec<i64>;
    let chunk_names: Vec<String>;
    let chunk_kinds: Vec<i32>;
    // "type id:original method name" -> index of the first function taking that type as self.
    let self_methods: Dict<String, i32>;
    var self_methods_built: Bool;
    static def new(result: MirPostResult, owner: String, partitions: i32 = 1) -> LlvmModuleEmitter {
        let emitter = LlvmModuleEmitter { result, cache: LlvmTypeCache.new(result.type_table, result.program),
            signatures: Dict<String, LlvmSignature>.with_capacity(16, 1), signature_order: Vec<String>.new(),
            function_names: Vec<String>.new(), symbol_names: Dict<i32, String>.with_capacity(16, 0),
            source_names: Dict<String, String>.with_capacity(16, 1), witness_names: Dict<String, String>.with_capacity(16, 1),
            globals: StringBuilder.new(), bodies: StringBuilder.new(), errors: Vec<String>.new(), string_id: 0, arc_helpers: false,
            alloc_helpers: false, char_helpers: false, frem_helpers: false, collection_metadata: false,
            owner, linkages: Dict<String, String>.with_capacity(16, 1),
            debug: false, debug_lines: StringBuilder.new(), next_meta: 16, debug_files: Dict<String, i32>.new(),
            debug_types: Dict<i32, i32>.new(), debug_unit: -1, debug_signature: -1, debug_declare: false,
            partitions, partition_bytes: 0, chunk_starts: Vec<i64>.new(), chunk_ends: Vec<i64>.new(), chunk_names: Vec<String>.new(), chunk_kinds: Vec<i32>.new(),
            self_methods: Dict<String, i32>.with_capacity(16, 1), self_methods_built: false };
        if owner.len() > 0 { emitter.cache.symbols = result.symbol_table; }
        emitter.reserve_functions(); emitter
    }
    def function_symbol(func: MirFunction) -> SymbolId? {
        if let symbol = func.symbol_id { return symbol; }
        for original in self.result.program.functions {
            if (original.name + "_resume").equals(func.name) { if let symbol = original.symbol_id { return symbol; } }
        }
        nil
    }
    def signature(signature: LlvmSignature) -> Void {
        if let old = self.signatures[signature.name] {
            var matches = old.result.equals(signature.result) && old.params.len() == signature.params.len();
            if matches { for i in 0..<old.params.len() { if !old.params[i].equals(signature.params[i]) { matches = false; } } }
            if !matches { self.errors.push("Conflicting LLVM signature for " + signature.name); }
            return;
        }
        self.signatures[signature.name] = signature; self.signature_order.push(signature.name);
    }
    def reserve_functions() -> Void {
        let first = Dict<String, i32>.with_capacity(16, 1); var main_index = -1;
        let functions = self.result.program.functions;
        for i in 0..<functions.len() {
            let func = functions[i]; if !first.contains(func.name) { first[func.name] = i; }
            if func.name.equals("main") { main_index = i; }
        }
        for i in 0..<functions.len() {
            let func = functions[i]; var name = func.name;
            var defined = true; var linkage = "";
            if func.name.equals("main") && i == main_index { name = "__rolang_user_main"; }
            else if (first[func.name] ?? i) != i || func.name.equals("main") {
                var identity = i; if let symbol = func.symbol_id { identity = symbol.id; }
                name += "." + identity.to_string();
            }
            if self.owner.len() > 0 && !name.equals("__rolang_user_main") {
                if let symbol = self.function_symbol(func) {
                    var key = abi_symbol_key(symbol, self.result.symbol_table, self.result.type_table);
                    if key.len() == 0 { self.errors.push("Missing module ABI identity for " + func.name); }
                    if let direct = func.symbol_id {} else { key += ":resume"; }
                    name = "__rl_" + sha256(key);
                    let owner = abi_symbol_owner(symbol, self.result.symbol_table);
                    var template = false;
                    if let origin = self.result.symbol_table.specialization_origin[symbol.id] { template = origin.type_args.len() > 0; }
                    if template || owner.starts_with("std:") { linkage = "weak_odr "; }
                    else if owner.len() > 0 && !owner.equals(self.owner) { defined = false; }
                } else { linkage = "internal "; }
            } else if !name.equals("__rolang_user_main") {
                // A whole program keeps its functions to itself, so one named like a C
                // library function (`rename`, `free`) cannot replace it for the runtime.
                // Split into modules, a function may be called from another module, so
                // it gets a name no C symbol has.
                linkage = "internal ";
                if self.partitions > 1 { name = "rl." + name; }
            }
            self.linkages[name] = linkage;
            self.function_names.push(name);
            if !self.source_names.contains(func.name) || i == main_index { self.source_names[func.name] = name; }
            if let symbol = func.symbol_id { self.symbol_names[symbol.id] = name; }
            let params = Vec<String>.new(); for arg in func.args { params.push(self.cache.spelling(arg.type_id)); }
            var result = self.cache.spelling(func.ret_type); if i == main_index && result.equals("void") { result = "i32"; }
            self.signature(LlvmSignature { name, result, params, defined });
        }
        for ext in self.result.program.externs {
            let params = Vec<String>.new(); for param in ext.params { params.push(self.cache.spelling(param.1)); }
            self.signature(LlvmSignature { name: ext.name, result: self.cache.spelling(ext.ret_type), params, defined: false });
            if let symbol = ext.symbol_id { self.symbol_names[symbol.id] = ext.name; }
        }
    }
    def resolve(name: String, symbol: SymbolId? = nil) -> String {
        if let id = symbol { if let found = self.symbol_names[id.id] { return found; } }
        self.source_names[name] ?? name
    }
    def call(builder: LlvmIrBuilder, name: String, result: String, values: Vec<LlvmValue>) -> LlvmValue {
        var external = true; if let signature = self.signatures[name] { external = !signature.defined; }
        if external && (name.equals("rt_string_char_at") || name.equals("rt_char_is_digit") || name.equals("rt_char_is_alpha") || name.equals("rt_char_is_alnum") || name.equals("rt_char_is_space")) {
            if !self.char_helpers {
                self.char_helpers = true;
                self.signature(LlvmSignature { name: "__rolang_string_char_at", result: "i32", params: ["ptr", "i32"], defined: true });
                for kind in ["digit", "alpha", "alnum", "space"] {
                    self.signature(LlvmSignature { name: "__rolang_char_is_" + kind, result: "i32", params: ["i32"], defined: true });
                }
                self.add_body("", llvm_char_helpers(), 0);
            }
            return self.call(builder, "__rolang_" + name.substring(3, (name.len() - 3) as i32), result, values);
        }
        if name.equals("__rolang_frem_f64") && !self.frem_helpers {
            self.frem_helpers = true;
            self.signature(LlvmSignature { name, result: "double", params: ["double", "double"], defined: true });
            self.signature(LlvmSignature { name: "fmod", result: "double", params: ["double", "double"], defined: false });
            for intrinsic in ["llvm.fabs.f64", "llvm.trunc.f64"] { self.signature(LlvmSignature { name: intrinsic, result: "double", params: ["double"], defined: false }); }
            self.signature(LlvmSignature { name: "llvm.fma.f64", result: "double", params: ["double", "double", "double"], defined: false });
            self.add_body("", llvm_frem_helper(), 0);
        }
        if name.equals("rt_obj_retain") || name.equals("rt_obj_release") {
            if !self.arc_helpers {
                self.arc_helpers = true;
                self.signature(LlvmSignature { name: "__rolang_obj_retain", result: "void", params: ["ptr"], defined: true });
                self.signature(LlvmSignature { name: "__rolang_obj_release", result: "void", params: ["ptr"], defined: true });
                self.signature(LlvmSignature { name: "rt_obj_release_slow", result: "void", params: ["ptr"], defined: false });
                self.add_body("", llvm_arc_helpers(), 0);
            }
            var helper = "__rolang_obj_retain"; if name.equals("rt_obj_release") { helper = "__rolang_obj_release"; }
            return self.call(builder, helper, result, values);
        }
        var signature = self.signatures[name];
        if let known = signature {} else {
            let params = Vec<String>.new(); for value in values { params.push(value.type); }
            let declared = LlvmSignature { name, result, params, defined: false }; self.signature(declared); signature = declared;
        }
        guard let known = signature else { return LlvmValue { type: result, text: "zeroinitializer" }; }
        if known.params.len() != values.len() { self.errors.push("LLVM call arity mismatch: " + name); }
        let args = Vec<LlvmValue>.new();
        for i in 0..<values.len() {
            var value = values[i]; if i < known.params.len() { value = builder.coerce(value, known.params[i]); }
            args.push(value);
        }
        builder.call(llvm_global(name), known.result, args)
    }
    def alloc_payload(builder: LlvmIrBuilder, size: i64, descriptor: i64, complete: Bool) -> LlvmValue {
        let args = [LlvmValue { type: "i64", text: size.to_string() }, LlvmValue { type: "i64", text: "8" }, LlvmValue { type: "i64", text: descriptor.to_string() }];
        var name = "rt_obj_alloc";
        if complete {
            name = "rt_obj_alloc_noinit";
            if size >= 0 && size + 32 <= 256 {
                if !self.alloc_helpers {
                    self.alloc_helpers = true;
                    self.signature(LlvmSignature { name: "__rolang_obj_alloc_fast", result: "ptr", params: ["i64", "i64", "i64", "i64"], defined: true });
                    self.signature(LlvmSignature { name: "rt_obj_alloc_noinit", result: "ptr", params: ["i64", "i64", "i64"], defined: false });
                    self.signature(LlvmSignature { name: "rt_gc_collect", result: "void", params: Vec<String>.new(), defined: false });
                    self.add_body("", llvm_alloc_helper(), 0);
                }
                let bins = [48, 64, 96, 128, 192, 256]; var bin = 0;
                while (bins[bin] as i64) < size + 32 { bin += 1; }
                args.push(LlvmValue { type: "i64", text: bin.to_string() }); name = "__rolang_obj_alloc_fast";
            }
        }
        self.call(builder, name, "ptr", args)
    }
    def alloc(builder: LlvmIrBuilder, type_id: TypeId, complete: Bool = false) -> LlvmValue {
        self.alloc_payload(builder, self.cache.payload_size(type_id), self.cache.descriptor(type_id), complete)
    }
    def collection_tags() -> Void {
        if self.collection_metadata { return; } self.collection_metadata = true;
        self.globals.append_line("!0 = !{!\"Rolang TBAA\"}");
        self.globals.append_line("!1 = !{!\"rolang collection header\", !0, i64 0}");
        self.globals.append_line("!2 = !{!\"rolang collection element\", !0, i64 0}");
        self.globals.append_line("!3 = !{!1, !1, i64 0}");
        self.globals.append_line("!4 = !{!2, !2, i64 0}");
    }
    def string_constant(builder: LlvmIrBuilder, text: String, type_id: TypeId) -> LlvmValue {
        let name = f".rolang.str.{self.string_id}"; self.string_id += 1;
        let bytes = StringBuilder.new(); let hex = "0123456789ABCDEF";
        for i in 0..<(text.len() as i32) {
            let byte = text.byte_at(i); bytes.append_byte(92 as u8);
            bytes.append_byte(hex.byte_at(byte / 16) as u8); bytes.append_byte(hex.byte_at(byte % 16) as u8);
        }
        bytes.append_byte(92 as u8); bytes.append("00");
        self.globals.append_line(llvm_global(name) + " = private unnamed_addr constant [" + (text.len() + 1).to_string() + " x i8] c\"" + bytes.to_string() + "\"");
        let handle = self.call(builder, "rt_string_from_rodata", "ptr", [LlvmValue { type: "ptr", text: llvm_global(name) }, LlvmValue { type: "i64", text: text.len().to_string() }]);
        // String's physical payload includes data, byte length, hash cache.
        let obj = self.alloc_payload(builder, 24, self.cache.descriptor(type_id), true);
        let data = builder.load("ptr", handle.text); let length = builder.load("i64", builder.gep(handle.text, "8"));
        builder.store(data, "ptr", builder.gep(obj.text, "32")); builder.store(length, "i64", builder.gep(obj.text, "40"));
        builder.store(LlvmValue { type: "i64", text: "0" }, "i64", builder.gep(obj.text, "48"));
        self.call(builder, "rt_free", "void", [handle]); obj
    }
    def witness_key(concrete: TypeId, protocol: TypeId) -> String { f"{concrete.id}:{protocol.id}" }
    def witness(concrete: TypeId, protocol: TypeId) -> String? { self.witness_names[self.witness_key(concrete, protocol)] }
    def type_method(type_id: TypeId, method: String) -> String? {
        if self.owner.len() > 0 { for func in self.result.program.functions {
            if func.is_method && func.args.len() > 0 && func.args[0].type_id == type_id {
                var matches = func.name.ends_with("_" + method);
                if let symbol = func.symbol_id {
                    var original = symbol;
                    while true { if let origin = self.result.symbol_table.specialization_origin[original.id] { original = origin.original_id; } else { break; } }
                    if let source = self.result.symbol_table.get_symbol(original) { if source.name.equals(method) { matches = true; } }
                    if matches { if let name = self.symbol_names[symbol.id] { return name; } }
                }
            }
        } }
        var name = self.cache.struct_name(type_id);
        if let info = self.result.type_table.get_type(type_id) { switch info.data {
            case .struct_type(let data): if let id = data.symbol_id { if let symbol = self.result.symbol_table.get_symbol(id) { name = mangle_name(symbol.name, data.type_args, self.result.type_table); } }
            case .enum_type(let data): if let symbol = self.result.symbol_table.get_symbol(data.symbol_id) { name = mangle_name(symbol.name, data.type_args, self.result.type_table); }
            case .primitive(let primitive): name = primitive.spelling();
            default: {}
        } }
        if let type_name = name {
            let candidate = self.resolve(type_name + "_" + method);
            if self.signatures.contains(candidate) { return candidate; }
        }
        // Generic extension methods are instantiated under their own names; find
        // the instance whose self is `type_id` and whose original is `method`.
        if !self.self_methods_built {
            self.self_methods_built = true;
            for i in 0..<self.result.program.functions.len() {
                let func = self.result.program.functions[i];
                if func.args.len() == 0 || !func.args[0].name.equals("self") { continue; }
                guard let symbol = func.symbol_id else { continue; }
                var original = symbol;
                while true { if let origin = self.result.symbol_table.specialization_origin[original.id] { original = origin.original_id; } else { break; } }
                if let source = self.result.symbol_table.get_symbol(original) {
                    let key = func.args[0].type_id.id.to_string() + ":" + source.name;
                    if !self.self_methods.contains(key) { self.self_methods[key] = i; }
                }
            }
        }
        if let index = self.self_methods[type_id.id.to_string() + ":" + method] { return self.function_names[index]; }
        nil
    }
    def emit_witnesses(arena: AstArena) -> Void {
        let checker = ConformanceChecker.new(arena, self.result.type_table, self.result.symbol_table);
        let resolver = TypeResolver.new(arena, self.result.type_table, self.result.symbol_table, nil, nil, nil, true);
        for symbol in self.result.symbol_table.symbols.values() { switch symbol.kind { case .extension:
            if let id = symbol.decl_node { if let node = arena.get(id) { switch node.form { case .extension_decl(let data):
                if let extended = data.extended_type { let concrete = resolver.resolve(extended);
                    for protocol in data.conformances { checker.register_extension(concrete, resolver.resolve(protocol), symbol.id); }
                }
                default: {}
            } } } default: {}
        } }
        let pairs = Vec<(TypeId, TypeId)>.new(); let seen = Dict<String, Bool>.with_capacity(16, 1);
        for func in self.result.program.functions { for id in func.block_order { if let block = func.get_block(id) { for op in block.ops { switch op {
            case .box_existential(let data): let key = self.witness_key(data.concrete_type, data.protocol_type);
                if !seen.contains(key) { seen[key] = true; pairs.push((data.concrete_type, data.protocol_type)); }
            default: {}
        } } } } }
        for pair in pairs {
            let concrete = pair.0; let protocol = pair.1; let key = self.witness_key(concrete, protocol);
            let name = f"__rolang_witness_{concrete.id}_{protocol.id}"; self.witness_names[key] = name;
            // The checker verified conformance before specialization; here witnesses are only
            // located, by requirement name when a specialized type no longer matches the source.
            let conformance = checker.check_conformance(concrete, protocol);
            guard let info = self.result.type_table.get_type(protocol) else { continue; }
            switch info.data { case .protocol(let data):
                let entries = Vec<String>.new();
                for requirement in data.func_requirements {
                    // Members depending on unfixed associated types cannot be called through this existential.
                    var open = self.result.type_table.has_type_variables(requirement.return_type);
                    for param in requirement.params { if self.result.type_table.has_type_variables(param) { open = true; } }
                    if open { entries.push("ptr null"); continue; }
                    var implementation: String? = nil;
                    for witness in conformance.witnesses { if witness.is_method && witness.requirement_name.equals(requirement.name) {
                        if let symbol = witness.implementation_symbol { implementation = self.symbol_names[symbol.id]; }
                        if let found = implementation {} else { implementation = self.type_method(concrete, witness.implementation_name); }
                    } }
                    if let found = implementation {} else { implementation = self.type_method(concrete, requirement.name); }
                    guard let target = implementation else { self.errors.push("Missing witness method: " + requirement.name); entries.push("ptr null"); continue; }
                    let thunk_name = name + "_" + requirement.name; let builder = LlvmIrBuilder.new(self.errors);
                    let params = Vec<String>.new(); params.push("ptr"); for param in requirement.params { params.push(self.cache.spelling(param)); }
                    let result = self.cache.spelling(requirement.return_type);
                    self.signature(LlvmSignature { name: thunk_name, result, params, defined: true });
                    let header = StringBuilder.new(); header.append("define internal " + result + " " + llvm_global(thunk_name) + "(ptr %self");
                    for i in 0..<requirement.params.len() { header.append(", " + params[i+1] + f" %arg{i}"); }
                    header.append(") {"); builder.line(header.to_string()); builder.line("entry:");
                    var receiver = LlvmValue { type: "ptr", text: "%self" };
                    if !self.cache.managed(concrete) { receiver = builder.load(self.cache.spelling(concrete), builder.gep("%self", "32")); }
                    let args = [receiver]; for i in 0..<requirement.params.len() { args.push(LlvmValue { type: params[i+1], text: f"%arg{i}" }); }
                    let returned = self.call(builder, target, result, args);
                    if result.equals("void") { builder.line("  ret void"); } else { builder.line("  ret " + returned.typed()); }
                    builder.line("}"); self.add_body(thunk_name, builder.output.to_string(), 1); entries.push("ptr " + llvm_global(thunk_name));
                }
                let initializer = StringBuilder.new(); for i in 0..<entries.len() { if i > 0 { initializer.append(", "); } initializer.append(entries[i]); }
                var linkage = ""; if self.owner.len() > 0 { linkage = "internal "; }
                self.globals.append_line(llvm_global(name) + " = " + linkage + f"constant [{entries.len()} x ptr] [" + initializer.to_string() + "]");
                default: {}
            }
        }
    }
    def emit_release_fields(descriptor: i64, fields: Vec<LlvmFieldDescriptor>) -> String {
        if fields.len() == 0 { return "null"; }
        let name = f"__rolang_release_fields_{descriptor}";
        let builder = LlvmIrBuilder.new(self.errors);
        builder.line("define internal void " + llvm_global(name) + "(ptr %payload) {"); builder.line("entry:");
        var tagged = false; for field in fields { if field.tag >= 0 { tagged = true; } }
        var tag = LlvmValue { type: "i32", text: "0" }; if tagged { tag = builder.load("i32", "%payload"); }
        for i in 0..<fields.len() {
            let field = fields[i]; let load = f"load_field_{i}"; let release = f"release_field_{i}"; let next = f"next_field_{i}";
            if field.tag >= 0 {
                let matches = builder.compare("icmp eq", tag, LlvmValue { type: "i32", text: field.tag.to_string() });
                builder.line("  br i1 " + matches.text + ", label %" + load + ", label %" + next); builder.line(load + ":");
            }
            let value = builder.load("ptr", builder.gep("%payload", field.offset.to_string()));
            let present = builder.compare("icmp ne", value, LlvmValue { type: "ptr", text: "null" });
            builder.line("  br i1 " + present.text + ", label %" + release + ", label %" + next); builder.line(release + ":");
            self.call(builder, "rt_obj_release", "void", [value]);
            builder.line("  br label %" + next); builder.line(next + ":");
        }
        builder.line("  ret void"); builder.line("}");
        self.signature(LlvmSignature { name, result: "void", params: ["ptr"], defined: true });
        self.add_body(name, builder.output.to_string(), 1); llvm_global(name)
    }
    def emit_descriptors() -> Void {
        let descriptors = Vec<String>.new(); let field_lists = Vec<Vec<LlvmFieldDescriptor>>.new();
        var index = 0;
        // Discover nested descriptors with a worklist; cycles add each type once.
        while index < self.cache.descriptor_types.len() {
            let type_id = self.cache.descriptor_types[index]; let fields = Vec<LlvmFieldDescriptor>.new();
            if let info = self.result.type_table.get_type(type_id) { switch info.data {
                case .struct_type | .closure:
                    for field in self.cache.fields(type_id) { if self.cache.managed(field.type_id) {
                        let target = self.cache.managed_inner(field.type_id);
                        fields.push(LlvmFieldDescriptor { offset: field.offset, type_id: self.cache.descriptor(target), tag: -1 });
                    } }
                case .enum_type:
                    for item in self.result.program.enums { if item.type_id == type_id { for case in item.cases {
                        for field in self.cache.enum_case(type_id, case.name) { if self.cache.managed(field.type_id) {
                            let target = self.cache.managed_inner(field.type_id);
                            fields.push(LlvmFieldDescriptor { offset: field.offset, type_id: self.cache.descriptor(target), tag: case.tag });
                        } }
                    } } }
                case .existential: fields.push(LlvmFieldDescriptor { offset: 8, type_id: -1, tag: -1 });
                default: {}
            } }
            field_lists.push(fields); index += 1;
        }
        // Sparse module descriptor IDs are never graph indices. Map both ways
        // after the discovery worklist closes, including nested/cyclic fields.
        let indices = Dict<i64, i32>.with_capacity(16, 0); let edges = Dict<i32, Vec<i32>>.with_capacity(16, 0);
        let conservative = Dict<i32, Bool>.with_capacity(16, 0);
        for i in 0..<self.cache.descriptor_types.len() { indices[self.cache.descriptor(self.cache.descriptor_types[i])] = i; }
        for i in 0..<self.cache.descriptor_types.len() {
            let targets = Vec<i32>.new();
            for field in field_lists[i] {
                if let target = indices[field.type_id] { targets.push(target); }
                else { conservative[i] = true; }
            }
            edges[i] = targets;
            let type_id = self.cache.descriptor_types[i];
            if let info = self.result.type_table.get_type(type_id) { switch info.data {
                // A function-typed field can contain a capturing closure whose
                // dynamic descriptor is not the static function descriptor.
                case .function | .closure | .existential: conservative[i] = true;
                default: {}
            } } else { conservative[i] = true; }
            if let name = self.type_method(type_id, "__gc_trace__") { conservative[i] = true; }
        }
        let cyclic = cyclic_capable_ids(self.cache.descriptor_types.len(), edges, conservative);
        let field_type = "{ i32, i64, i32, i32 }"; let desc_type = "{ i64, i64, i32, i32, ptr, ptr, i32, ptr }"; let hash_rows = Vec<String>.new();
        let field_text = StringBuilder.new(); var field_count = 0;
        for i in 0..<self.cache.descriptor_types.len() {
            let type_id = self.cache.descriptor_types[i]; let fields = field_lists[i]; let start = field_count;
            for field in fields {
                if field_count > 0 { field_text.append(", "); }
                field_text.append(field_type + f" {{ i32 {field.offset}, i64 {field.type_id}, i32 {field.tag}, i32 0 }}"); field_count += 1;
            }
            var release = "null"; var trace = "null";
            if let name = self.type_method(type_id, "__release__") { release = llvm_global(name); }
            if let name = self.type_method(type_id, "__gc_trace__") { trace = llvm_global(name); }
            let size = self.cache.payload_size(type_id);
            let descriptor = self.cache.descriptor(type_id);
            var acyclic = 1; if cyclic.contains(i) { acyclic = 0; }
            let release_fields = self.emit_release_fields(descriptor, fields);
            // Hashable keys: hash() -> u64 and __eq__(Self) -> Bool.
            var hash = "null"; var equals = "null";
            if let hash_name = self.type_method(type_id, "hash") { if let equals_name = self.type_method(type_id, "__eq__") {
                if let h = self.signatures[hash_name] { if let e = self.signatures[equals_name] {
                    if h.result.equals("i64") && h.params.len() == 1 && e.result.equals("i1") && e.params.len() == 2 {
                        hash = llvm_global(hash_name); equals = llvm_global(equals_name);
                    }
                } }
            } }
            descriptors.push(desc_type + f" {{ i64 {descriptor}, i64 {size}, i32 {fields.len()}, i32 {start}, ptr " + release + ", ptr " + trace + f", i32 {acyclic}, ptr " + release_fields + " }");
            hash_rows.push("{ ptr, ptr } { ptr " + hash + ", ptr " + equals + " }");
        }
        let desc_text = StringBuilder.new(); for i in 0..<descriptors.len() { if i > 0 { desc_text.append(", "); } desc_text.append(descriptors[i]); }
        var linkage = ""; if self.owner.len() > 0 { linkage = "internal "; }
        self.globals.append_line("@RT_TYPE_DESCRIPTORS = " + linkage + f"constant [{descriptors.len()} x " + desc_type + "] [" + desc_text.to_string() + "]");
        self.globals.append_line("@RT_TYPE_DESCRIPTOR_COUNT = " + linkage + f"constant i32 {descriptors.len()}");
        let hash_text = StringBuilder.new(); for i in 0..<hash_rows.len() { if i > 0 { hash_text.append(", "); } hash_text.append(hash_rows[i]); }
        self.globals.append_line("@RT_TYPE_HASH_FUNCTIONS = " + linkage + f"constant [{hash_rows.len()} x {{ ptr, ptr }}] [" + hash_text.to_string() + "]");
        self.globals.append_line("@RT_TYPE_HASH_FUNCTION_COUNT = " + linkage + f"constant i32 {hash_rows.len()}");
        self.globals.append_line("@RT_TYPE_FIELD_DESCRIPTORS = " + linkage + f"constant [{field_count} x " + field_type + "] [" + field_text.to_string() + "]");
        self.globals.append_line("@RT_TYPE_FIELD_DESCRIPTOR_COUNT = " + linkage + f"constant i32 {field_count}");
        if self.owner.len() > 0 { self.emit_type_registration(field_count); }
        for error in self.cache.errors { self.errors.push(error); }
    }
    def emit_type_registration(field_count: i32) -> Void {
        let keys = StringBuilder.new(); let hex = "0123456789ABCDEF";
        for i in 0..<self.cache.descriptor_types.len() {
            let key = abi_type_key(self.cache.descriptor_types[i], self.result.symbol_table, self.result.type_table);
            let bytes = StringBuilder.new();
            for j in 0..<(key.len() as i32) { let byte = key.byte_at(j); bytes.append_byte(92 as u8);
                bytes.append_byte(hex.byte_at(byte / 16) as u8); bytes.append_byte(hex.byte_at(byte % 16) as u8); }
            bytes.append("\\00");
            self.globals.append_line(f"@.rl.type.key.{i} = private constant [{key.len()+1} x i8] c\"" + bytes.to_string() + "\"");
            if i > 0 { keys.append(", "); } keys.append(f"ptr @.rl.type.key.{i}");
        }
        let count = self.cache.descriptor_types.len();
        self.globals.append_line(f"@.rl.type.keys = private constant [{count} x ptr] [" + keys.to_string() + "]");
        self.globals.append_line("@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @__rl_register_types, ptr null }]");
        self.signature(LlvmSignature { name: "rt_register_module_types", result: "void", params: ["ptr", "i32", "ptr", "i32", "ptr"], defined: false });
        let register = self.bodies.len();
        self.bodies.append_line("define internal void @__rl_register_types() {"); self.bodies.append_line("entry:");
        self.bodies.append_line(f"  call void @rt_register_module_types(ptr @RT_TYPE_DESCRIPTORS, i32 {count}, ptr @RT_TYPE_FIELD_DESCRIPTORS, i32 {field_count}, ptr @.rl.type.keys)");
        self.signature(LlvmSignature { name: "rt_register_module_hash_functions", result: "void", params: ["ptr", "ptr", "i32"], defined: false });
        self.bodies.append_line(f"  call void @rt_register_module_hash_functions(ptr @RT_TYPE_DESCRIPTORS, ptr @RT_TYPE_HASH_FUNCTIONS, i32 {count})");
        self.bodies.append_line("  ret void"); self.bodies.append_line("}");
        self.chunk_starts.push(register); self.chunk_ends.push(self.bodies.len()); self.chunk_names.push("__rl_register_types"); self.chunk_kinds.push(2);
    }
    def add_body(name: String, text: String, kind: i32) -> Void {
        self.chunk_starts.push(self.bodies.len()); self.bodies.append(text);
        self.chunk_ends.push(self.bodies.len()); self.chunk_names.push(name); self.chunk_kinds.push(kind);
    }
    def emit(arena: AstArena) -> LlvmResult {
        // Hooks are runtime callbacks, including on structs never allocated
        // by this program. Reject a wrong ABI before emitting any LLVM.
        for item in self.result.program.structs {
            for method in ["__release__", "__gc_trace__"] {
                if let name = self.type_method(item.type_id, method) {
                    if let signature = self.signatures[name] {
                        var count = 1; if method.equals("__gc_trace__") { count = 3; }
                        var valid = signature.result.equals("void") && signature.params.len() == count;
                        for param in signature.params { if !param.equals("ptr") { valid = false; } }
                        if !valid { self.errors.push(method + " on struct '" + item.name + "' has an invalid signature; expected void with " + count.to_string() + " pointer parameter(s)"); }
                    }
                }
            }
        }
        for func in self.result.program.functions { for local in func.locals {
            if self.result.type_table.is_error(local.type_id) { self.errors.push("Cannot emit LLVM for unresolved MIR type in " + func.name + ": " + local.name); }
        } }
        if self.errors.len() > 0 { return LlvmResult { text: "", errors: self.errors, modules: Vec<String>.new() }; }
        // Preserve source type names in opaque-pointer LLVM dumps.
        for item in self.result.program.structs { self.globals.append_line("; struct " + item.name + ": payload " + self.cache.payload_size(item.type_id).to_string() + " bytes"); }
        for item in self.result.program.enums { self.globals.append_line("; enum " + item.name + ": payload " + self.cache.payload_size(item.type_id).to_string() + " bytes"); }
        self.emit_witnesses(arena);
        for i in 0..<self.result.program.functions.len() {
            let func = self.result.program.functions[i]; let name = self.function_names[i];
            if let signature = self.signatures[name] { if !signature.defined { continue; } }
            let emitter = LlvmFunctionEmitter.new(self, func, name); emitter.emit(); self.add_body(name, emitter.ir.output.to_string(), 1);
        }
        self.emit_descriptors();
        if self.partitions > 1 && self.debug_unit < 0 {
            let modules = self.partition();
            if modules.len() > 1 { return LlvmResult { text: modules[0], errors: self.errors, modules }; }
        }
        let output = StringBuilder.new(); output.append_line("; Rolang full MIR backend: LLVM text, 64-bit pointers, 32-byte ARC header");
        output.append(self.globals.to_string());
        for name in self.signature_order { if let signature = self.signatures[name] { if !signature.defined { output.append_line(signature.declaration()); } } }
        output.append(self.bodies.to_string());
        if self.debug_unit >= 0 {
            if self.debug_declare { output.append_line("declare void @llvm.dbg.declare(metadata, metadata, metadata)"); }
            let version = self.meta("!{i32 7, !\"Dwarf Version\", i32 4}");
            let format = self.meta("!{i32 2, !\"Debug Info Version\", i32 3}");
            output.append_line(f"!llvm.dbg.cu = !{{!{self.debug_unit}}}");
            output.append_line(f"!llvm.module.flags = !{{!{version}, !{format}}}");
            output.append(self.debug_lines.to_string());
        }
        LlvmResult { text: output.to_string(), errors: self.errors, modules: Vec<String>.new() }
    }
    // Splits the program into modules clang compiles in parallel. Functions
    // are spread in order, balanced by size; inline helpers are copied into
    // every module; a function called from another module becomes hidden
    // (whole-program functions are named `rl.*` then). Private constants are
    // copied; other globals are defined in the first module and declared in
    // the others. Returns one module when the program is too small to split.
    def partition() -> Vec<String> {
        let bodies = self.bodies.to_string();
        var total: i64 = 0;
        for i in 0..<self.chunk_kinds.len() { if self.chunk_kinds[i] == 1 { total += self.chunk_ends[i] - self.chunk_starts[i]; } }
        var count = self.partitions;
        if self.partition_bytes > 0 && (total / self.partition_bytes) < (count as i64) { count = (total / self.partition_bytes) as i32; }
        if count < 2 { return Vec<String>.new(); }
        // Modules by size, in order; functions by their quoted LLVM names.
        let module_of = Vec<i32>.new(); let defined_in = Dict<String, i32>.with_capacity(16, 1); let raw_names = Dict<String, String>.with_capacity(16, 1);
        let share = total / (count as i64) + 1; var current = 0; var filled: i64 = 0;
        for i in 0..<self.chunk_kinds.len() {
            var module = 0;
            if self.chunk_kinds[i] == 1 {
                if filled >= share * ((current + 1) as i64) && current < count - 1 { current += 1; }
                module = current; filled += self.chunk_ends[i] - self.chunk_starts[i];
                let quoted = llvm_global(self.chunk_names[i]); defined_in[quoted] = module; raw_names[quoted] = self.chunk_names[i];
            }
            module_of.push(module);
        }
        // Functions each module calls from another one.
        let exported = Dict<String, Bool>.with_capacity(16, 1); let imports = Vec<Dict<String, Bool>>.new();
        for m in 0..<count { imports.push(Dict<String, Bool>.with_capacity(16, 1)); }
        for i in 0..<self.chunk_kinds.len() {
            if self.chunk_kinds[i] == 0 { continue; }
            llvm_note_imports(bodies, self.chunk_starts[i] as i32, self.chunk_ends[i] as i32, module_of[i], defined_in, exported, imports[module_of[i]]);
        }
        let globals = self.globals.to_string();
        llvm_note_imports(globals, 0, globals.len() as i32, 0, defined_in, exported, imports[0]);
        // What every module but the first needs of the globals.
        let shared = StringBuilder.new();
        for line in globals.split("\n") {
            if line.len() == 0 || line.starts_with(";") || line.starts_with("@llvm.") { continue; }
            if line.starts_with("!") || line.contains(" = private ") || line.contains(" = external ") { shared.append_line(line); continue; }
            if let declaration = llvm_global_declaration(line) { shared.append_line(declaration); }
        }
        let externs = StringBuilder.new();
        for name in self.signature_order { if let signature = self.signatures[name] { if !signature.defined { externs.append_line(signature.declaration()); } } }
        let helpers = StringBuilder.new();
        for i in 0..<self.chunk_kinds.len() { if self.chunk_kinds[i] == 0 { helpers.append(bodies.substring(self.chunk_starts[i] as i32, (self.chunk_ends[i] - self.chunk_starts[i]) as i32)); } }
        let modules = Vec<String>.new();
        for m in 0..<count {
            let output = StringBuilder.new(); output.append_line(f"; Rolang full MIR backend: LLVM text, 64-bit pointers, 32-byte ARC header (module {m + 1} of {count})");
            if m == 0 { output.append(globals); } else { output.append(shared.to_string()); }
            output.append(externs.to_string());
            for quoted in imports[m].keys() {
                if let name = raw_names[quoted] { if let signature = self.signatures[name] { output.append_line(signature.declaration()); } }
            }
            output.append(helpers.to_string());
            for i in 0..<self.chunk_kinds.len() {
                if self.chunk_kinds[i] == 0 || module_of[i] != m { continue; }
                var text = bodies.substring(self.chunk_starts[i] as i32, (self.chunk_ends[i] - self.chunk_starts[i]) as i32);
                if exported.contains(llvm_global(self.chunk_names[i])) {
                    let at = text.find("define internal ");
                    if at >= 0 { text = text.substring(0, at) + "define hidden " + text.substring(at + 16, text.len() as i32 - at - 16); }
                }
                output.append(text);
            }
            modules.push(output.to_string());
        }
        modules
    }
    def meta(text: String, distinct: Bool = false) -> i32 {
        let id = self.next_meta; self.next_meta += 1;
        var prefix = ""; if distinct { prefix = "distinct "; }
        self.debug_lines.append_line(f"!{id} = {prefix}{text}");
        id
    }
    def debug_file(path: String) -> i32 {
        if let known = self.debug_files[path] { return known; }
        let id = self.meta(f"!DIFile(filename: {llvm_quote(path_basename(path))}, directory: {llvm_quote(path_dirname(path))})");
        self.debug_files[path] = id;
        if self.debug_unit < 0 {
            self.debug_unit = self.meta(f"!DICompileUnit(language: DW_LANG_C99, file: !{id}, producer: \"rolangc\", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)", true);
            self.debug_signature = self.meta("!DISubroutineType(types: !{})");
        }
        id
    }
    // Variable types: numbers and Bool as base types, managed objects as named pointers.
    def debug_type(type_id: TypeId) -> i32? {
        if let known = self.debug_types[type_id.id] { return known; }
        let table = self.result.type_table;
        let name = table.format_type(type_id);
        var text = "";
        if let info = table.get_type(type_id) { switch info.data {
            case .primitive(let primitive):
                let width = primitive.integer_width();
                if width > 0 {
                    var encoding = "DW_ATE_unsigned"; if primitive.is_signed() { encoding = "DW_ATE_signed"; }
                    text = f"!DIBasicType(name: {llvm_quote(name)}, size: {width}, encoding: {encoding})";
                } else if primitive.is_float() {
                    var size = 64; switch primitive { case .f32: size = 32; default: {} }
                    text = f"!DIBasicType(name: {llvm_quote(name)}, size: {size}, encoding: DW_ATE_float)";
                } else { switch primitive {
                    case .bool_type: text = f"!DIBasicType(name: \"Bool\", size: 8, encoding: DW_ATE_boolean)";
                    default: {}
                } }
            default: {}
        } }
        if text.len() == 0 && self.cache.spelling(type_id).equals("ptr") {
            // A typedef keeps the Rolang type name visible in debuggers.
            var pointer = self.debug_types[-1] ?? -1;
            if pointer < 0 { pointer = self.meta("!DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)"); self.debug_types[-1] = pointer; }
            text = f"!DIDerivedType(tag: DW_TAG_typedef, name: {llvm_quote(name)}, baseType: !{pointer})";
        }
        if text.len() == 0 { return nil; }
        let id = self.meta(text);
        self.debug_types[type_id.id] = id;
        id
    }
}

struct LlvmFunctionEmitter {
    let module: LlvmModuleEmitter;
    let func: MirFunction;
    let name: String;
    let ir: LlvmIrBuilder;
    let local_types: Dict<i32, TypeId>;
    let address_sources: Dict<i32, MirLocalId>;
    // Debug information: the function's DISubprogram (-1 without -g) and its DILocations.
    var debug_scope: i32;
    var debug_file: i32;
    var debug_line: i32;
    let debug_locations: Dict<String, i32>;
    static def new(module: LlvmModuleEmitter, func: MirFunction, name: String) -> LlvmFunctionEmitter {
        let emitter = LlvmFunctionEmitter { module, func, name, ir: LlvmIrBuilder.new(module.errors), local_types: Dict<i32, TypeId>.with_capacity(16, 0), address_sources: Dict<i32, MirLocalId>.with_capacity(16, 0),
            debug_scope: -1, debug_file: -1, debug_line: 0, debug_locations: Dict<String, i32>.new() };
        for local in func.locals { emitter.local_types[local.id.id] = local.type_id; }
        // Recover only single-definition address casts. Reassignments in any
        // block invalidate provenance, independent of block emission order.
        let writes = Dict<i32, i32>.with_capacity(16, 0);
        for id in func.block_order { if let block = func.get_block(id) { for op in block.ops {
            if let result = mir_op_result(op) { writes[result.id] = (writes[result.id] ?? 0) + 1; }
            switch op {
                case .assign(let data) | .store(let data): if data.place.projections.len() == 0 { writes[data.place.base.id] = (writes[data.place.base.id] ?? 0) + 1; }
                case .cast_op(let data): if module.result.type_table.format_type(data.target_type).equals("RawPtr") { switch data.operand {
                    case .copy(let place) | .move(let place): if place.projections.len() == 0 { emitter.address_sources[data.result.id] = place.base; }
                    default: {}
                } }
                default: {}
            }
        } } }
        let invalid = Vec<i32>.new(); for key in emitter.address_sources.keys() { if (writes[key] ?? 0) != 1 { invalid.push(key); } }
        for key in invalid { emitter.address_sources.remove(key); }
        emitter
    }
    def type(type_id: TypeId) -> String { self.module.cache.spelling(type_id) }
    // With -g, the first source position in the function; functions without one get no debug info.
    def first_location() -> MirDebugLocationData? {
        if !self.module.debug { return nil; }
        for id in self.func.block_order { if let block = self.func.get_block(id) { for op in block.ops {
            switch op { case .debug_location(let data): return data; default: {} }
        } } }
        nil
    }
    def begin_debug(at: MirDebugLocationData) -> i32 {
        self.debug_file = self.module.debug_file(at.file);
        self.debug_line = at.line;
        var display = self.name; if display.equals("__rolang_user_main") { display = "main"; }
        self.debug_scope = self.module.meta(f"!DISubprogram(name: {llvm_quote(display)}, linkageName: {llvm_quote(self.name)}, scope: !{self.debug_file}, file: !{self.debug_file}, line: {at.line}, type: !{self.module.debug_signature}, scopeLine: {at.line}, spFlags: DISPFlagDefinition, unit: !{self.module.debug_unit})", true);
        self.debug_scope
    }
    def locate(at: MirDebugLocationData) -> Void {
        if self.debug_scope < 0 { return; }
        let key = f"{at.line}:{at.column}";
        var id = self.debug_locations[key] ?? -1;
        if id < 0 {
            id = self.module.meta(f"!DILocation(line: {at.line}, column: {at.column}, scope: !{self.debug_scope})");
            self.debug_locations[key] = id;
        }
        self.ir.debug = f", !dbg !{id}";
    }
    // Named user variables and parameters, described at their stack slots.
    def declare_variables() -> Void {
        var arg_index = 0;
        for local in self.func.locals {
            var arg = 0;
            if local.is_arg { arg_index += 1; arg = arg_index; }
            // Compiler-made locals and the async frame parameter stay hidden.
            if local.name.starts_with("__") || local.name.len() == 0 || local.name.equals("_frame") { continue; }
            if !local.is_arg { if let sid = local.symbol_id {} else { continue; } }
            if self.type(local.type_id).equals("void") { continue; }
            guard let type = self.module.debug_type(local.type_id) else { continue; }
            var argument = ""; if arg > 0 { argument = f"arg: {arg}, "; }
            let variable = self.module.meta(f"!DILocalVariable(name: {llvm_quote(local.name)}, {argument}scope: !{self.debug_scope}, file: !{self.debug_file}, line: {self.debug_line}, type: !{type})");
            self.ir.line(f"  call void @llvm.dbg.declare(metadata ptr {self.local(local.id)}, metadata !{variable}, metadata !DIExpression())");
            self.module.debug_declare = true;
        }
    }
    def constant(type: String, text: String) -> LlvmValue { LlvmValue { type, text } }
    def local(id: MirLocalId) -> String { f"%local{id.id}" }
    def result(id: MirLocalId, value: LlvmValue) -> Void {
        guard let type_id = self.local_types[id.id] else { self.module.errors.push(f"Missing MIR local {id.id} in {self.func.name}"); return; }
        let type = self.type(type_id); if type.equals("void") { return; }
        let coerced = self.ir.coerce(value, type, self.module.result.type_table.is_signed_integer(type_id));
        self.ir.store(coerced, type, self.local(id));
    }
    def place(place: MirPlace) -> String {
        var pointer = self.local(place.base); var current = self.local_types[place.base.id] ?? place.type_id;
        if place.projections.len() > 0 && self.module.cache.managed(current) { pointer = self.ir.gep(self.ir.load("ptr", pointer).text, "32"); }
        for i in 0..<place.projections.len() { let projection = place.projections[i]; switch projection {
            case .field(let name, let type):
                if let field = self.module.cache.field(current, name) { pointer = self.ir.gep(pointer, field.offset.to_string()); }
                else { self.module.errors.push("Missing LLVM field " + name + " on " + self.module.result.type_table.format_type(current)); }
                current = type;
            case .index(let index, let type):
                let value = self.ir.coerce(self.operand(index), "i64", false);
                let offset = self.ir.binary("mul", value, self.constant("i64", self.module.cache.storage_size(type).to_string()));
                pointer = self.ir.gep(pointer, offset.text); current = type;
            case .deref(let type): pointer = self.ir.load("ptr", pointer).text; current = type;
        }
            if i+1 < place.projections.len() { switch projection { case .field:
                if self.module.cache.managed(current) { pointer = self.ir.gep(self.ir.load("ptr", pointer).text, "32"); }
                default: {}
            } }
        } pointer
    }
    def operand(operand: MirOperand) -> LlvmValue {
        switch operand {
            case .copy(let place) | .move(let place):
                let type = self.type(place.type_id); if type.equals("void") { return self.constant("i64", "0"); }
                return self.ir.load(type, self.place(place));
            case .constant(let data):
                let type = self.type(data.type_id);
                switch data.value {
                    case .integer(let value): return self.constant(type, value);
                    case .floating(let value): return self.constant(type, llvm_float(value, type.equals("float")));
                    case .boolean(let value): var text = "0"; if value { text = "1"; } return self.constant("i1", text);
                    case .text(let value): return self.module.string_constant(self.ir, value, data.type_id);
                    case .none: switch data.kind {
                        case .nil: return self.constant("ptr", "null");
                        case .unit: return self.constant("i64", "0");
                        default: return self.constant(type, "zeroinitializer");
                    }
                }
        }
    }
    def store(place: MirPlace, operand: MirOperand) -> Void {
        let value = self.operand(operand); let pointer = self.place(place); let type = self.type(place.type_id);
        self.ir.store(self.ir.coerce(value, type, self.module.result.type_table.is_signed_integer(operand.type_id())), type, pointer);
    }
    def call(name: String, result: String, args: Vec<LlvmValue>) -> LlvmValue { self.module.call(self.ir, name, result, args) }
    def emit() -> Void {
        guard let signature = self.module.signatures[self.name] else { return; }
        let header = StringBuilder.new(); header.append("define " + (self.module.linkages[self.name] ?? "") + signature.result + " " + llvm_global(self.name) + "(");
        for i in 0..<self.func.args.len() { if i > 0 { header.append(", "); } header.append(signature.params[i] + f" %arg{i}"); }
        // Frame pointers keep panic backtraces and profilers able to walk the stack.
        header.append(") \"frame-pointer\"=\"non-leaf\"");
        let first = self.first_location();
        if let at = first { header.append(f" !dbg !{self.begin_debug(at)}"); }
        header.append(" {"); self.ir.line(header.to_string());
        if let at = first { self.locate(at); }
        // A dedicated prologue keeps every alloca outside MIR loops and safely
        // dominates all blocks even when MIR block order differs from entry.
        self.ir.line("entry:");
        for local in self.func.locals { let type = self.type(local.type_id); if !type.equals("void") { self.ir.line("  " + self.local(local.id) + " = alloca " + type); } }
        if self.debug_scope >= 0 { self.declare_variables(); }
        for i in 0..<self.func.args.len() { let arg = self.func.args[i]; self.ir.store(self.constant(signature.params[i], f"%arg{i}"), signature.params[i], self.local(arg.id)); }
        self.ir.line(f"  br label %bb{self.func.entry_block.id}");
        for id in self.func.block_order { if let block = self.func.get_block(id) {
            self.ir.line(f"bb{id.id}:"); for op in block.ops { self.operation(op); }
            if let term = block.terminator { self.terminator(term, signature.result); } else { self.ir.line("  unreachable"); }
        } }
        self.ir.line("}");
    }
    def terminator(term: MirTerm, return_type: String) -> Void {
        switch term {
            case .branch(let data): self.ir.line(f"  br label %bb{data.target.id}");
            case .cond_branch(let data): let value = self.ir.coerce(self.operand(data.condition), "i1", false);
                self.ir.line("  br i1 " + value.text + f", label %bb{data.true_target.id}, label %bb{data.false_target.id}");
            case .switch_int(let data): let value = self.operand(data.value); self.ir.line("  switch " + value.typed() + f", label %bb{data.default.id} [");
                for item in data.cases { self.ir.line("    " + value.type + " " + item.0 + f", label %bb{item.1.id}"); } self.ir.line("  ]");
            case .return_stmt(let data):
                if let operand = data.value { let value = self.ir.coerce(self.operand(operand), return_type, self.module.result.type_table.is_signed_integer(operand.type_id())); self.ir.line("  ret " + value.typed()); }
                else if return_type.equals("void") { self.ir.line("  ret void"); } else if self.name.equals("__rolang_user_main") { self.ir.line("  ret i32 0"); }
                else { self.module.errors.push("Missing LLVM return value in " + self.name); self.ir.line("  unreachable"); }
            case .unreachable: self.ir.line("  unreachable");
        }
    }
    def operation(op: MirOp) -> Void {
        switch op {
            case .assign(let data): self.store(data.place, data.value);
            case .store(let data): self.store(data.place, data.value);
            case .load(let data): self.result(data.result, self.ir.load(self.type(data.place.type_id), self.place(data.place)));
            case .bin_op(let data): self.binary(data);
            case .cmp_op(let data): self.comparison(data);
            case .unary_op(let data): self.unary(data);
            case .cast_op(let data): self.cast(data);
            case .make_struct(let data): self.make_struct(data);
            case .make_enum(let data): self.make_enum(data);
            case .make_some(let data): self.result(data.result, self.some(self.operand(data.value), data.result_type));
            case .make_none(let data): self.result(data.result, self.constant(self.type(data.result_type), "zeroinitializer"));
            case .extract_field(let data): self.extract_field(data);
            case .extract_closure_capture(let data): self.extract_capture(data);
            case .extract_enum_payload(let data): self.extract_payload(data);
            case .get_tag(let data): self.get_tag(data);
            case .retain(let data): self.call("rt_obj_retain", "void", [self.operand(data.operand)]);
            case .release(let data): self.call("rt_obj_release", "void", [self.operand(data.operand)]);
            case .alloc_obj(let data): self.result(data.result, self.module.alloc(self.ir, data.result_type));
            case .clone(let data): self.result(data.result, self.call("rt_obj_clone", "ptr", [self.operand(data.value)]));
            case .gc_check: self.call("rt_gc_collect", "void", Vec<LlvmValue>.new());
            case .call_static(let data): self.static_call(data);
            case .call_v_table(let data): self.virtual_call(data.result, data.receiver, data.receiver.type_id(), data.method_name, data.args, data.result_type);
            case .call_witness(let data): self.witness_call(data);
            case .make_closure(let data): self.make_closure(data);
            case .call_closure(let data): self.closure_call(data);
            case .box_existential(let data): self.box_existential(data);
            case .existential_check_type(let data): self.check_existential(data);
            case .existential_unbox(let data): self.unbox_existential(data);
            case .alloc_async_frame(let data): self.result(data.result, self.module.alloc(self.ir, data.frame_type));
            case .task_spawn(let data): self.task_spawn(data);
            case .task_join(let data): let value = self.call("rt_task_join", "ptr", [self.operand(data.task_handle)]); if let result = data.result { self.result(result, value); }
            case .task_yield: self.call("rt_task_yield", "void", Vec<LlvmValue>.new());
            case .task_complete(let data): self.task_complete(data);
            case .scheduler_run(let data): self.scheduler_run(data);
            case .task_get_result(let data): self.task_result(data);
            case .debug_location(let data): self.locate(data);
            case .suspend(let data): self.call("rt_task_yield", "void", Vec<LlvmValue>.new()); if let result = data.result { self.result(result, self.constant(self.type(data.result_type), "zeroinitializer")); }
        }
    }
    def binary(data: MirBinOpData) -> Void {
        let type = self.type(data.result_type);
        let a = self.ir.coerce(self.operand(data.left), type, self.module.result.type_table.is_signed_integer(data.left.type_id()));
        var b = self.ir.coerce(self.operand(data.right), type, self.module.result.type_table.is_signed_integer(data.right.type_id()));
        let floating = type.equals("float") || type.equals("double"); let signed = self.module.result.type_table.is_signed_integer(data.result_type);
        var instruction = "";
        switch data.op {
            case .add: instruction = "add"; if floating { instruction = "fadd contract"; }
            case .sub: instruction = "sub"; if floating { instruction = "fsub contract"; }
            case .mul: instruction = "mul"; if floating { instruction = "fmul contract"; }
            case .div | .mod:
                var remainder = false; switch data.op { case .mod: remainder = true; default: {} }
                if floating {
                    instruction = "fdiv contract";
                    if remainder {
                        if type.equals("double") { self.result(data.result, self.call("__rolang_frem_f64", "double", [a, b])); return; }
                        instruction = "frem";
                    }
                }
                else {
                    let zero = self.ir.compare("icmp eq", b, self.constant(type, "0"));
                    let panic = self.ir.fresh(); let next = self.ir.fresh();
                    self.ir.line("  br i1 " + zero.text + ", label %" + panic + ", label %" + next);
                    self.ir.line(panic + ":"); var name = "rt_panic_divide_by_zero"; if remainder { name = "rt_panic_remainder_by_zero"; }
                    self.call(name, "void", Vec<LlvmValue>.new()); self.ir.line("  unreachable"); self.ir.line(next + ":");
                    instruction = "udiv"; if remainder { instruction = "urem"; }
                    if signed {
                        var minimum = "-9223372036854775808";
                        if type.equals("i8") { minimum = "-128"; } else if type.equals("i16") { minimum = "-32768"; } else if type.equals("i32") { minimum = "-2147483648"; }
                        let is_min = self.ir.compare("icmp eq", a, self.constant(type, minimum));
                        let is_negative_one = self.ir.compare("icmp eq", b, self.constant(type, "-1"));
                        let overflow = self.ir.binary("and", is_min, is_negative_one);
                        b = self.ir.value(type, "select i1 " + overflow.text + ", " + type + " 1, " + b.typed());
                        instruction = "sdiv"; if remainder { instruction = "srem"; }
                    }
                }
            case .bit_and: instruction = "and"; case .bit_or: instruction = "or"; case .bit_xor: instruction = "xor";
            case .shl: instruction = "shl"; b = self.ir.binary("and", b, self.constant(type, (llvm_width(type)-1).to_string()));
            case .shr: instruction = "lshr"; if signed { instruction = "ashr"; } b = self.ir.binary("and", b, self.constant(type, (llvm_width(type)-1).to_string()));
        }
        self.result(data.result, self.ir.binary(instruction, a, b));
    }
    def comparison(data: MirCmpOpData) -> Void {
        var a = self.operand(data.left); var b = self.operand(data.right);
        if a.type.starts_with("{") && b.type.equals("ptr") || b.type.starts_with("{") && a.type.equals("ptr") {
            var optional = a; if b.type.starts_with("{") { optional = b; }
            let tag = self.ir.value("i1", "extractvalue " + optional.typed() + ", 0");
            var pred = "icmp eq"; switch data.op { case .ne: pred = "icmp ne"; default: {} }
            self.result(data.result, self.ir.compare(pred, tag, self.constant("i1", "0"))); return;
        }
        let left_signed = self.module.result.type_table.is_signed_integer(data.left.type_id());
        let right_signed = self.module.result.type_table.is_signed_integer(data.right.type_id());
        var width = llvm_width(a.type); let right_width = llvm_width(b.type);
        if width > 0 && right_width > 0 {
            if right_width > width { width = right_width; }
            if left_signed != right_signed {
                var signed_width = llvm_width(a.type); var unsigned_width = right_width;
                if right_signed { signed_width = right_width; unsigned_width = llvm_width(a.type); }
                if signed_width <= unsigned_width && width < 64 { width = 64; }
            }
            let type = f"i{width}"; a = self.ir.coerce(a, type, left_signed); b = self.ir.coerce(b, type, right_signed);
        }
        if a.type.equals("float") && b.type.equals("double") { a = self.ir.cast("fpext", a, "double"); }
        if b.type.equals("float") && a.type.equals("double") { b = self.ir.cast("fpext", b, "double"); }
        var pred = ""; let floating = a.type.equals("float") || a.type.equals("double");
        if floating { switch data.op { case .eq: pred = "fcmp oeq"; case .ne: pred = "fcmp une"; case .lt: pred = "fcmp olt"; case .le: pred = "fcmp ole"; case .gt: pred = "fcmp ogt"; case .ge: pred = "fcmp oge"; } }
        else {
            var prefix = "u"; if left_signed || right_signed { prefix = "s"; }
            switch data.op { case .eq: pred = "eq"; case .ne: pred = "ne"; case .lt: pred = prefix+"lt"; case .le: pred = prefix+"le"; case .gt: pred = prefix+"gt"; case .ge: pred = prefix+"ge"; }
            pred = "icmp " + pred;
        }
        self.result(data.result, self.ir.compare(pred, a, b));
    }
    def unary(data: MirUnaryOpData) -> Void {
        let value = self.operand(data.operand); var result = value;
        switch data.op {
            case .neg:
                if value.type.equals("float") || value.type.equals("double") { result = self.ir.value(value.type, "fneg " + value.typed()); }
                else { result = self.ir.binary("sub", self.constant(value.type, "0"), value); }
            case .not: result = self.ir.compare("icmp eq", value, self.constant(value.type, "0"));
            case .bit_not: result = self.ir.binary("xor", value, self.constant(value.type, "-1"));
        } self.result(data.result, result);
    }
    def cast(data: MirCastOpData) -> Void {
        let target = self.type(data.target_type);
        if self.module.result.type_table.format_type(data.target_type).equals("RawPtr") { switch data.operand {
            case .copy(let place) | .move(let place): if place.projections.len() == 0 {
                self.result(data.result, self.constant("ptr", self.local(place.base))); return;
            }
            default: {}
        } }
        let value = self.operand(data.operand); let source = value.type;
        // `p as T` is the inverse of `x as RawPtr`, which takes x's address: it
        // reads the T reference stored at p.
        if self.module.result.type_table.format_type(data.operand.type_id()).equals("RawPtr") && self.module.cache.managed(data.target_type) {
            self.result(data.result, self.ir.load("ptr", value.text)); return;
        }
        var result = value; let source_width = llvm_width(source); let target_width = llvm_width(target);
        let source_float = source.equals("float") || source.equals("double"); let target_float = target.equals("float") || target.equals("double");
        let signed = self.module.result.type_table.is_signed_integer(data.operand.type_id());
        if source.equals(target) {}
        else if target.equals("i1") && source_width > 0 { result = self.ir.compare("icmp ne", value, self.constant(source, "0")); }
        else if target.equals("i1") && source_float { result = self.ir.compare("fcmp one", value, self.constant(source, "0.0")); }
        else if source_width > 0 && target_width > 0 { result = self.ir.coerce(value, target, signed); }
        else if source_float && target_float {
            var op = "fptrunc"; if source.equals("float") { op = "fpext"; } result = self.ir.cast(op, value, target);
        }
        else if source_width > 0 && target_float {
            var op = "uitofp"; if signed { op = "sitofp"; } result = self.ir.cast(op, value, target);
        }
        else if source_float && target_width > 0 {
            var op = "fptoui"; if self.module.result.type_table.is_signed_integer(data.target_type) { op = "fptosi"; }
            var suffix = "f64"; if source.equals("float") { suffix = "f32"; }
            result = self.call("llvm." + op + ".sat." + target + "." + suffix, target, [value]);
        }
        else if source.equals("ptr") && target_width > 0 { result = self.ir.cast("ptrtoint", value, target); }
        else if source_width > 0 && target.equals("ptr") { result = self.ir.cast("inttoptr", self.ir.coerce(value, "i64", false), "ptr"); }
        else if target.equals("void") { return; }
        else if target.equals("ptr") {
            let slot = self.ir.value("ptr", "alloca " + source); self.ir.store(value, source, slot.text); result = slot;
        }
        else { self.module.errors.push("Unsupported LLVM cast: " + source + " -> " + target); }
        self.result(data.result, result);
    }
    def some(value: LlvmValue, type_id: TypeId) -> LlvmValue {
        let type = self.type(type_id); if type.equals("ptr") { return value; }
        let flag = self.ir.value(type, "insertvalue " + type + " zeroinitializer, i1 1, 0");
        self.ir.value(type, "insertvalue " + flag.typed() + ", " + value.typed() + ", 1")
    }
    def make_struct(data: MirMakeStructData) -> Void {
        let values = Vec<(LlvmField, LlvmValue)>.new();
        for pair in data.fields {
            let value = self.operand(pair.1);
            if let field = self.module.cache.field(data.struct_type, pair.0) {
                values.push((field, self.ir.coerce(value, self.type(field.type_id), self.module.result.type_table.is_signed_integer(pair.1.type_id()))));
            } else { self.module.errors.push("Unknown struct field: " + pair.0); }
        }
        let stored = Dict<i64, Bool>.with_capacity(16, 0); for pair in values { stored[pair.0.offset] = true; }
        var complete = true; for field in self.module.cache.fields(data.struct_type) { if !stored.contains(field.offset) { complete = false; } }
        let obj = self.module.alloc(self.ir, data.struct_type, complete);
        for pair in values { self.ir.store(pair.1, self.type(pair.0.type_id), self.ir.gep(obj.text, (32+pair.0.offset).to_string())); }
        self.result(data.result, obj);
    }
    def make_enum(data: MirMakeEnumData) -> Void {
        let layout = self.module.cache.enum_case(data.enum_type, data.case_name); let values = Vec<LlvmValue>.new();
        for i in 0..<data.payload.len() {
            var value = self.operand(data.payload[i]);
            if i < layout.len() { value = self.ir.coerce(value, self.type(layout[i].type_id), self.module.result.type_table.is_signed_integer(data.payload[i].type_id())); }
            values.push(value);
        }
        let obj = self.module.alloc(self.ir, data.enum_type, values.len() == layout.len());
        self.ir.store(self.constant("i32", data.tag.to_string()), "i32", self.ir.gep(obj.text, "32"));
        for i in 0..<values.len() {
            if i >= layout.len() { self.module.errors.push("Missing enum payload layout: " + data.case_name); break; }
            self.ir.store(values[i], values[i].type, self.ir.gep(obj.text, (32+layout[i].offset).to_string()));
        } self.result(data.result, obj);
    }
    def extract_field(data: MirExtractFieldData) -> Void {
        let object = self.operand(data.aggregate); let fields = self.module.cache.fields(data.aggregate.type_id());
        if data.field_index < 0 || data.field_index >= fields.len() { self.module.errors.push("Invalid LLVM field index: " + data.field_name); return; }
        self.result(data.result, self.ir.load(self.type(data.result_type), self.ir.gep(object.text, (32+fields[data.field_index].offset).to_string())));
    }
    def extract_capture(data: MirExtractClosureCaptureData) -> Void {
        let closure = self.operand(data.closure); let fields = self.module.cache.fields(data.closure.type_id());
        if data.capture_index < 0 || data.capture_index >= fields.len() { self.module.errors.push("Invalid LLVM capture index"); return; }
        self.result(data.result, self.ir.load(self.type(data.result_type), self.ir.gep(closure.text, (32+fields[data.capture_index].offset).to_string())));
    }
    def extract_payload(data: MirExtractEnumPayloadData) -> Void {
        let value = self.operand(data.enum_val);
        if let inner = self.module.result.type_table.get_optional_inner(data.enum_val.type_id()) {
            if value.type.equals("ptr") { self.result(data.result, value); }
            else { self.result(data.result, self.ir.value(self.type(data.result_type), "extractvalue " + value.typed() + ", 1")); }
            return;
        }
        let fields = self.module.cache.enum_case(data.enum_val.type_id(), data.case_name);
        if data.payload_index < 0 || data.payload_index >= fields.len() { self.module.errors.push("Invalid enum payload index: " + data.case_name); return; }
        self.result(data.result, self.ir.load(self.type(data.result_type), self.ir.gep(value.text, (32+fields[data.payload_index].offset).to_string())));
    }
    def get_tag(data: MirGetTagData) -> Void {
        let value = self.operand(data.enum_val); var tag = self.constant("i32", "0");
        if let inner = self.module.result.type_table.get_optional_inner(data.enum_val.type_id()) {
            if value.type.equals("ptr") { tag = self.ir.compare("icmp ne", value, self.constant("ptr", "null")); }
            else { tag = self.ir.value("i1", "extractvalue " + value.typed() + ", 0"); }
        } else { tag = self.ir.load("i32", self.ir.gep(value.text, "32")); }
        self.result(data.result, tag);
    }
    def scalar_address(operand: MirOperand, allow_heap: Bool) -> MirLocalId? {
        switch operand {
            case .copy(let place) | .move(let place):
                if place.projections.len() != 0 { return nil; }
                if let source = self.address_sources[place.base.id] { if let type_id = self.local_types[source.id] {
                    let type = self.type(type_id);
                    if !allow_heap && self.module.cache.managed(type_id) { return nil; }
                    if llvm_width(type) > 0 || type.equals("float") || type.equals("double") || type.equals("ptr") { return source; }
                } }
            default: {}
        } nil
    }
    def collection_load(type: String, pointer: String, header: Bool) -> LlvmValue {
        self.module.collection_tags(); var tag = "!4"; if header { tag = "!3"; }
        self.ir.value(type, "load " + type + ", ptr " + pointer + ", align 1, !tbaa " + tag)
    }
    def collection_store(value: LlvmValue, pointer: String) -> Void {
        self.module.collection_tags(); self.ir.line("  store " + value.typed() + ", ptr " + pointer + ", align 1, !tbaa !4");
    }
    def index_panic(index: LlvmValue, length: LlvmValue) -> Void {
        self.call("rt_panic_index_out_of_bounds", "void", [self.ir.coerce(index, "i64"), self.ir.coerce(length, "i64")]); self.ir.line("  unreachable");
    }
    def vec_slot(vec: LlvmValue, index: LlvmValue, type_id: TypeId) -> String {
        let valid = self.ir.fresh(); let null_panic = self.ir.fresh();
        let is_null = self.ir.compare("icmp eq", vec, self.constant("ptr", "null"));
        self.ir.line("  br i1 " + is_null.text + ", label %" + null_panic + ", label %" + valid);
        self.ir.line(null_panic + ":"); self.index_panic(index, self.constant("i32", "0")); self.ir.line(valid + ":");
        let length = self.collection_load("i32", vec.text, true);
        let oob = self.ir.compare("icmp uge", index, length); let panic = self.ir.fresh(); let ok = self.ir.fresh();
        self.ir.line("  br i1 " + oob.text + ", label %" + panic + ", label %" + ok);
        self.ir.line(panic + ":"); self.index_panic(index, length); self.ir.line(ok + ":");
        let offset = self.ir.binary("mul", self.ir.cast("zext", index, "i64"), self.constant("i64", self.module.cache.storage_size(type_id).to_string()));
        self.ir.gep(self.ir.gep(vec.text, "16"), offset.text)
    }
    def dict_slot(dict: LlvmValue, index: LlvmValue) -> String {
        let key = self.collection_load("i64", self.ir.gep(dict.text, "16"), true);
        let value = self.collection_load("i64", self.ir.gep(dict.text, "24"), true);
        let stride = self.ir.binary("add", key, value);
        let offset = self.ir.binary("add", self.ir.binary("mul", index, stride), key);
        self.ir.gep(self.ir.gep(dict.text, "56"), offset.text)
    }
    def collection_call(data: MirCallStaticData) -> Bool {
        // Resolve first so a same-named Rolang function is never intercepted.
        let name = self.module.resolve(data.func_name, data.func_symbol);
        if let signature = self.module.signatures[name] { if signature.defined { return false; } }
        if name.equals("rt_gvec_len") {
            if data.args.len() != 1 { return false; } guard let result = data.result else { return false; }
            let vec = self.operand(data.args[0]); let empty = self.ir.fresh(); let read = self.ir.fresh(); let done = self.ir.fresh();
            let is_null = self.ir.compare("icmp eq", vec, self.constant("ptr", "null"));
            self.ir.line("  br i1 " + is_null.text + ", label %" + empty + ", label %" + read);
            self.ir.line(empty + ":"); self.result(result, self.constant("i32", "0")); self.ir.line("  br label %" + done);
            self.ir.line(read + ":"); self.result(result, self.collection_load("i32", vec.text, true)); self.ir.line("  br label %" + done); self.ir.line(done + ":"); return true;
        }
        let vec_get = name.equals("rt_gvec_get"); let vec_set = name.equals("rt_gvec_set");
        let dict_get = name.equals("rt_dict_get_at"); let dict_set = name.equals("rt_dict_set_at");
        if !vec_get && !vec_set && !dict_get && !dict_set { return false; }
        if data.args.len() != 3 { return false; }
        guard let source = self.scalar_address(data.args[2], vec_get) else { return false; }
        guard let type_id = self.local_types[source.id] else { return false; }
        let type = self.type(type_id); let handle = self.operand(data.args[0]); var index = self.operand(data.args[1]);
        if vec_get || vec_set {
            index = self.ir.coerce(index, "i32"); let slot = self.vec_slot(handle, index, type_id);
            if vec_get {
                let value = self.collection_load(type, slot, false);
                if self.module.cache.managed(type_id) { self.call("rt_obj_retain", "void", [value]); }
                self.result(source, value);
            } else { self.collection_store(self.ir.load(type, self.local(source)), slot); }
            return true;
        }
        index = self.ir.coerce(index, "i64");
        let bounds = self.ir.fresh(); let oob = self.ir.fresh(); let ok = self.ir.fresh(); let done = self.ir.fresh();
        let is_null = self.ir.compare("icmp eq", handle, self.constant("ptr", "null"));
        self.ir.line("  br i1 " + is_null.text + ", label %" + done + ", label %" + bounds); self.ir.line(bounds + ":");
        let length = self.collection_load("i64", handle.text, true); let outside = self.ir.compare("icmp uge", index, length);
        self.ir.line("  br i1 " + outside.text + ", label %" + oob + ", label %" + ok); self.ir.line(oob + ":");
        if dict_get { self.result(source, self.constant(type, "zeroinitializer")); }
        self.ir.line("  br label %" + done); self.ir.line(ok + ":"); let slot = self.dict_slot(handle, index);
        if dict_get { self.result(source, self.collection_load(type, slot, false)); }
        else { self.collection_store(self.ir.load(type, self.local(source)), slot); }
        self.ir.line("  br label %" + done); self.ir.line(done + ":"); true
    }
    def static_call(data: MirCallStaticData) -> Void {
        if self.collection_call(data) { return; }
        let name = self.module.resolve(data.func_name, data.func_symbol); let args = Vec<LlvmValue>.new();
        let signature = self.module.signatures[name];
        for i in 0..<data.args.len() {
            var value = self.operand(data.args[i]);
            if let known = signature { if i < known.params.len() { value = self.ir.coerce(value, known.params[i], self.module.result.type_table.is_signed_integer(data.args[i].type_id())); } }
            args.push(value);
        }
        let value = self.call(name, self.type(data.result_type), args);
        if let result = data.result { if !value.type.equals("void") { self.result(result, value); } }
    }
    def make_closure(data: MirMakeClosureData) -> Void {
        let fields = self.module.cache.fields(data.result_type); let values = Vec<LlvmValue>.new();
        for capture in data.captures { values.push(self.operand(capture)); }
        let object = self.module.alloc(self.ir, data.result_type);
        let name = self.module.resolve(data.func_name);
        if !self.module.signatures.contains(name) { self.module.errors.push("Missing closure function: " + name); }
        self.ir.store(self.constant("ptr", llvm_global(name)), "ptr", self.ir.gep(object.text, "32"));
        for i in 0..<values.len() {
            if i >= fields.len() { self.module.errors.push("Missing closure capture layout"); break; }
            self.ir.store(values[i], self.type(fields[i].type_id), self.ir.gep(object.text, (32+fields[i].offset).to_string()));
        } self.result(data.result, object);
    }
    def closure_call(data: MirCallClosureData) -> Void {
        let closure = self.operand(data.closure); let function = self.ir.load("ptr", self.ir.gep(closure.text, "32"));
        let args = [closure]; for operand in data.args { args.push(self.operand(operand)); }
        let value = self.ir.call(function.text, self.type(data.result_type), args);
        if let result = data.result { self.result(result, value); }
    }
    def protocol(type_id: TypeId) -> TypeId {
        if let info = self.module.result.type_table.get_type(type_id) { switch info.data { case .existential(let data): return data.protocol_id; default: {} } } type_id
    }
    def virtual_call(result: MirLocalId?, receiver: MirOperand, witness_type: TypeId, name: String, operands: Vec<MirOperand>, result_type: TypeId) -> Void {
        let object = self.operand(receiver); let protocol = self.protocol(witness_type); var index = -1;
        if let info = self.module.result.type_table.get_type(protocol) { switch info.data { case .protocol(let data):
            for i in 0..<data.func_requirements.len() { if data.func_requirements.get(i).name.equals(name) { index = i; } }
            default: {}
        } }
        if index < 0 { self.module.errors.push("Missing protocol method: " + name); return; }
        let table = self.ir.load("ptr", self.ir.gep(object.text, "32"));
        let value = self.ir.load("ptr", self.ir.gep(object.text, "40"));
        let function = self.ir.load("ptr", self.ir.gep(table.text, (index*8).to_string()));
        let args = [value]; for operand in operands { args.push(self.operand(operand)); }
        let returned = self.ir.call(function.text, self.type(result_type), args);
        if let local = result { self.result(local, returned); }
    }
    def witness_call(data: MirCallWitnessData) -> Void {
        if data.args.len() == 0 { self.module.errors.push("Witness call has no receiver"); return; }
        if let info = self.module.result.type_table.get_type(data.witness_type) { switch info.data {
            case .struct_type | .enum_type | .primitive:
                guard let target = self.module.type_method(data.witness_type, data.method_name) else { self.module.errors.push("Missing concrete witness method: " + data.method_name); return; }
                let values = Vec<LlvmValue>.new(); for operand in data.args { values.push(self.operand(operand)); }
                let returned = self.call(target, self.type(data.result_type), values);
                if let result = data.result { self.result(result, returned); } return;
            default: {}
        } }
        let args = Vec<MirOperand>.new(); for i in 1..<data.args.len() { args.push(data.args[i]); }
        self.virtual_call(data.result, data.args[0], data.witness_type, data.method_name, args, data.result_type);
    }
    def box_existential(data: MirBoxExistentialData) -> Void {
        let value = self.operand(data.value); var concrete = value;
        if !self.module.cache.managed(data.concrete_type) {
            concrete = self.module.alloc(self.ir, data.concrete_type);
            self.ir.store(value, value.type, self.ir.gep(concrete.text, "32"));
        }
        let object = self.module.alloc(self.ir, data.result_type); var table = "null";
        if let name = self.module.witness(data.concrete_type, data.protocol_type) { table = llvm_global(name); }
        else { self.module.errors.push("Missing existential witness table"); }
        self.ir.store(self.constant("ptr", table), "ptr", self.ir.gep(object.text, "32"));
        self.ir.store(concrete, "ptr", self.ir.gep(object.text, "40")); self.result(data.result, object);
    }
    def check_existential(data: MirExistentialCheckTypeData) -> Void {
        let object = self.operand(data.existential); let witness = self.ir.load("ptr", self.ir.gep(object.text, "32"));
        var value = self.constant("i1", "0");
        if self.module.owner.len() > 0 {
            let concrete = self.ir.load("ptr", self.ir.gep(object.text, "40"));
            let descriptor = self.ir.load("i64", self.ir.gep(concrete.text, "8"));
            value = self.ir.compare("icmp eq", descriptor, self.constant("i64", self.module.cache.descriptor(data.concrete_type).to_string()));
        } else if let name = self.module.witness(data.concrete_type, data.protocol_type) { value = self.ir.compare("icmp eq", witness, self.constant("ptr", llvm_global(name))); }
        self.result(data.result, value);
    }
    def unbox_existential(data: MirExistentialUnboxData) -> Void {
        let object = self.operand(data.existential); var value = self.ir.load("ptr", self.ir.gep(object.text, "40"));
        if !self.module.cache.managed(data.concrete_type) { value = self.ir.load(self.type(data.concrete_type), self.ir.gep(value.text, "32")); }
        self.result(data.result, value);
    }
    def task_spawn(data: MirTaskSpawnData) -> Void {
        guard let frame = self.module.cache.frame(data.async_func_name) else { self.module.errors.push("Missing async frame: " + data.async_func_name); return; }
        var pointer = self.constant("ptr", "null");
        if let operand = data.frame { pointer = self.operand(operand); } else { pointer = self.module.alloc(self.ir, frame.type_id); }
        let resume_name = self.module.resolve(data.async_func_name+"_resume");
        if !self.module.signatures.contains(resume_name) { self.module.errors.push("Missing async resume function: " + resume_name); return; }
        let handle = self.call("rt_task_spawn", "ptr", [self.constant("ptr", llvm_global(resume_name)), pointer]);
        if let field = self.module.cache.field(frame.type_id, "$handle") { self.ir.store(handle, "ptr", self.ir.gep(pointer.text, (32+field.offset).to_string())); }
        self.result(data.result, handle);
    }
    def task_complete(data: MirTaskCompleteData) -> Void {
        let handle = self.operand(data.task_handle); var pointer = self.constant("ptr", "null"); var kind = "0";
        if let operand = data.result {
            let value = self.operand(operand);
            if self.module.cache.managed(operand.type_id()) { self.call("rt_obj_retain", "void", [value]); pointer = value; kind = "2"; }
            else {
                var size = self.module.cache.storage_size(operand.type_id()); if size < 1 { size = 1; }
                pointer = self.call("rt_alloc", "ptr", [self.constant("i64", size.to_string()), self.constant("i64", self.module.cache.storage_align(operand.type_id()).to_string())]);
                self.ir.store(value, value.type, pointer.text); kind = "1";
            }
        }
        self.call("rt_task_complete_owned", "void", [handle, pointer, self.constant("i32", kind)]);
    }
    def task_result(data: MirTaskGetResultData) -> Void {
        let handle = self.operand(data.task_handle); self.call("rt_task_join", "ptr", [handle]);
        var name = "rt_task_borrow_result"; if data.consume { name = "rt_task_take_result"; }
        let pointer = self.call(name, "ptr", [handle]); let type = self.type(data.result_type);
        if !type.equals("void") {
            var value = pointer;
            if !self.module.cache.managed(data.result_type) {
                value = self.ir.load(type, pointer.text); if data.consume { self.call("rt_free", "void", [pointer]); }
            } else if !data.consume { self.call("rt_obj_retain", "void", [value]); }
            self.result(data.result, value);
        }
        if data.consume { self.call("rt_task_destroy", "void", [handle]); }
    }
    def scheduler_run(data: MirSchedulerRunData) -> Void {
        if let operand = data.until_handle {
            let handle = self.operand(operand); self.call("rt_task_join", "ptr", [handle]);
            if data.destroy_after { self.call("rt_task_destroy", "void", [handle]); }
        } else { self.call("rt_scheduler_run", "void", Vec<LlvmValue>.new()); }
    }
}

// Up to `partitions` modules, each with at least `partition_bytes` of function text (whole programs without -g).
pub def compile_to_llvm(result: MirPostResult, arena: AstArena, owner: String = "", debug: Bool = false, partitions: i32 = 1, partition_bytes: i64 = 0) -> LlvmResult {
    var count = partitions; if owner.len() > 0 || debug { count = 1; }
    let emitter = LlvmModuleEmitter.new(result, owner, count); emitter.debug = debug; emitter.partition_bytes = partition_bytes; emitter.emit(arena)
}

// Records the functions defined in another module that text[start..<end] (in `module`) refers to.
def llvm_note_imports(text: String, start: i32, end: i32, module: i32, defined_in: Dict<String, i32>, exported: Dict<String, Bool>, imports: Dict<String, Bool>) -> Void {
    var at = text.find_from("@\"", start);
    while at >= 0 && at < end {
        let close = text.find_from("\"", at + 2);
        if close < 0 { return; }
        let quoted = text.substring(at, close + 1 - at);
        if let owner = defined_in[quoted] { if owner != module { exported[quoted] = true; imports[quoted] = true; } }
        at = text.find_from("@\"", close + 1);
    }
}

// `@name = external constant T` for a global defined as `@name = [linkage] constant|global T value`.
def llvm_global_declaration(line: String) -> String? {
    let equals = line.find(" = ");
    if equals < 0 { return nil; }
    var at = -1; var kind = "";
    for candidate in ["constant ", "global "] {
        let found = line.find_from(candidate, equals);
        if found >= 0 && (at < 0 || found < at) { at = found; kind = candidate; }
    }
    if at < 0 { return nil; }
    let start = at + kind.len() as i32; var end = start;
    let first = line.byte_at(start);
    if first == 91 || first == 123 {
        // A bracketed type: up to the matching bracket.
        var depth = 0;
        while end < line.len() as i32 {
            let byte = line.byte_at(end);
            if byte == 91 || byte == 123 { depth += 1; }
            if byte == 93 || byte == 125 { depth -= 1; if depth == 0 { end += 1; break; } }
            end += 1;
        }
    } else {
        while end < line.len() as i32 && line.byte_at(end) != 32 { end += 1; }
    }
    line.substring(0, equals) + " = external " + kind + line.substring(start, end - start)
}
