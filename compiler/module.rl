// Module identities and dependency ordering.
// Paths are strings; the source loader supplies canonical identities.
pub import "ast.rl"
pub import "symbols.rl"
import std.path
import std.collections
import std.set

pub enum ModuleState {
    case discovered; case parsed; case resolved; case typechecked; case compiled; case error;
}
pub struct ModuleExport {
    pub let name: String;
    pub let symbol_id: SymbolId;
    pub let kind: String;
    pub let visibility: String;
}
pub struct ModuleExports {
    pub let exports: Dict<String, ModuleExport>;
    pub let extension_exports: Vec<ExtensionExport>;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let imported_symbols: Dict<String, SymbolId>;
    pub static def new() -> ModuleExports {
        ModuleExports {
            exports: Dict<String, ModuleExport>.with_capacity(16, 1),
            extension_exports: Vec<ExtensionExport>.new(),
            node_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            imported_symbols: Dict<String, SymbolId>.with_capacity(16, 1)
        }
    }
}
pub struct Module {
    pub let name: String;
    pub let path: String;
    pub var source: String? = nil;
    pub var program: NodeId? = nil;
    pub var symbol_table: SymbolTable? = nil;
    pub let exports: Dict<String, ModuleExport>;
    pub let extension_exports: Vec<ExtensionExport>;
    pub let dependencies: Set<String>;
    pub let dependents: Set<String>;
    pub var state: ModuleState;
    pub let errors: Vec<String>;
    pub let import_paths: Dict<String, String>;
    pub static def new(name: String, path: String) -> Module {
        Module {
            name, path, source: nil, program: nil, symbol_table: nil,
            exports: Dict<String, ModuleExport>.with_capacity(16, 1),
            extension_exports: Vec<ExtensionExport>.new(),
            dependencies: Set<String>.new(), dependents: Set<String>.new(),
            state: ModuleState.discovered(), errors: Vec<String>.new(), import_paths: Dict<String, String>.with_capacity(16, 1)
        }
    }
    pub def qualified_name(local_name: String) -> String { f"{self.name}.{local_name}" }
    pub def has_export(name: String) -> Bool { self.exports.contains(name) }
    pub def get_export(name: String) -> ModuleExport? { self.exports[name] }
    pub def add_export(name: String, symbol_id: SymbolId, kind: String,
                       visibility: String = "internal") -> Void {
        self.exports[name] = ModuleExport { name, symbol_id, kind, visibility };
    }
    pub def add_extension_export(method_name: String, method_symbol_id: SymbolId,
                                extended_type_name: String) -> Void {
        self.extension_exports.push(ExtensionExport {
            type_name: extended_type_name, method_name, symbol_id: method_symbol_id,
            visibility: "internal"
        });
    }
    pub def get_extension_methods(type_name: String) -> Vec<ImportedMethod> {
        let result = Vec<ImportedMethod>.new();
        for item in self.extension_exports {
            if item.type_name.equals(type_name) {
                result.push(ImportedMethod { name: item.method_name, symbol_id: item.symbol_id });
            }
        }
        result
    }
    pub def add_dependency(name: String) -> Void { self.dependencies.add(name); }
    pub def add_dependent(name: String) -> Void { self.dependents.add(name); }
}
pub struct ModuleOrderResult {
    pub let order: Vec<String>;
    pub let error: String?;
}
pub struct CompilationOrderResult {
    pub let modules: Vec<Module>;
    pub let error: String?;
}
pub struct ModuleGraph {
    pub let modules: Dict<String, Module>;
    pub let source_roots: Vec<String>;
    pub static def new() -> ModuleGraph {
        ModuleGraph { modules: Dict<String, Module>.with_capacity(16, 1), source_roots: Vec<String>.new() }
    }
    pub def add_module(module: Module) -> Void { self.modules[module.name] = module; }
    pub def get_module(name: String) -> Module? { self.modules[name] }
    pub def has_module(name: String) -> Bool { self.modules.contains(name) }
    pub def get_all_modules() -> Vec<Module> { self.modules.values() }
    pub def add_dependency(from_module: String, to_module: String) -> Void {
        if let source = self.modules[from_module] { source.add_dependency(to_module); }
        if let target = self.modules[to_module] { target.add_dependent(from_module); }
    }
    pub def topological_sort() -> ModuleOrderResult {
        let degree = Dict<String, i32>.with_capacity(16, 1);
        let queue = Vec<String>.new();
        let result = Vec<String>.new();
        for item in self.modules.entries() {
            degree[item.key] = item.value.dependencies.len() as i32;
            if item.value.dependencies.len() == 0 { queue.push(item.key); }
        }
        var head = 0;
        while head < queue.len() {
            let name = queue[head]; head += 1;
            result.push(name);
            for item in self.modules.entries() {
                if item.value.dependencies.contains(name) {
                    let remaining = (degree[item.key] ?? 0) - 1;
                    degree[item.key] = remaining;
                    if remaining == 0 { queue.push(item.key); }
                }
            }
        }
        if result.len() != self.modules.len() {
            let remaining = Vec<String>.new();
            for item in self.modules.entries() {
                if (degree[item.key] ?? 0) > 0 { remaining.push(item.key); }
            }
            return ModuleOrderResult {
                order: result, error: "Circular dependency detected involving: " + join_strings(remaining, ", ")
            };
        }
        ModuleOrderResult { order: result, error: nil }
    }
    pub def get_compilation_order() -> CompilationOrderResult {
        let order = self.topological_sort();
        let modules = Vec<Module>.new();
        if let error = order.error { return CompilationOrderResult { modules, error }; }
        for name in order.order { if let module = self.modules[name] { modules.push(module); } }
        CompilationOrderResult { modules, error: nil }
    }
}

pub def module_name_from_path(path: String, source_root: String) -> String {
    let path_parts = Vec<String>.new();
    let root_parts = Vec<String>.new();
    for part in path.split("/") { if !part.is_empty() && !part.equals(".") { path_parts.push(part); } }
    for part in source_root.split("/") { if !part.is_empty() && !part.equals(".") { root_parts.push(part); } }
    var prefix = root_parts.len() <= path_parts.len();
    if path.starts_with("/") != source_root.starts_with("/") { prefix = false; }
    if prefix {
        for index in 0..<root_parts.len() {
            if !root_parts[index].equals(path_parts[index]) { prefix = false; break; }
        }
    }
    var start = 0;
    if prefix { start = root_parts.len(); }
    let names = Vec<String>.new();
    if !prefix && path.starts_with("/") { names.push("/"); }
    for index in start..<path_parts.len() { names.push(path_parts[index]); }
    if names.len() > 0 {
        let last = names.len() - 1;
        let name = names[last];
        var dot = -1;
        for index in 1..<(name.len() as i32) { if name.byte_at(index) == 46 { dot = index; } }
        if dot > 0 { names[last] = name.substring(0, dot); }
    }
    join_strings(names, ".")
}
