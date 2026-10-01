// Symbols and scopes. AST references are stable NodeIds.
pub import "ids.rl"
pub import "source.rl"
import "frozen.rl"

pub enum Namespace { case type; case value; }
pub enum SymbolKind {
    case variable; case function; case extern_func; case parameter;
    case enum_case; case field; case struct_type; case enum_type; case protocol;
    case type_alias; case generic_param; case associated_type;
    case builtin_type; case extension;

    pub def is_indexed_type() -> Bool {
        switch self {
            case .struct_type | .enum_type | .protocol | .builtin_type | .generic_param | .type_alias: true;
            default: false;
        }
    }
}
pub enum ScopeKind {
    case module; case type; case function; case block;
    case lambda; case for_loop; case switch_case;
}

pub struct Symbol {
    pub let id: SymbolId;
    pub var name: String;
    pub var kind: SymbolKind;
    pub var namespace: Namespace;
    pub var span: Span? = nil;
    pub var decl_node: NodeId? = nil;
    pub var is_mutable: Bool = false;
    pub var visibility: String = "internal";
    pub var is_extension_method: Bool = false;
}

pub struct Scope {
    pub let kind: ScopeKind;
    pub let parent: Scope?;
    pub let types: Dict<String, SymbolId>;
    pub let values: Dict<String, SymbolId>;

    pub static def new(kind: ScopeKind, parent: Scope? = nil) -> Scope {
        Scope { kind, parent, types: Dict<String, SymbolId>.with_capacity(16, 1), values: Dict<String, SymbolId>.with_capacity(16, 1) }
    }
    pub def lookup_type(name: String) -> SymbolId? {
        if let found = self.types[name] { return found; }
        if let parent = self.parent { return parent.lookup_type(name); }
        nil
    }
    pub def lookup_value(name: String) -> SymbolId? {
        if let found = self.values[name] { return found; }
        if let parent = self.parent { return parent.lookup_value(name); }
        nil
    }
    pub def define_type(name: String, symbol_id: SymbolId) -> Bool {
        if self.types.contains(name) { return false; }
        self.types[name] = symbol_id;
        true
    }
    pub def define_value(name: String, symbol_id: SymbolId) -> Bool {
        if self.values.contains(name) { return false; }
        self.values[name] = symbol_id;
        true
    }
    pub def has_type_local(name: String) -> Bool { self.types.contains(name) }
    pub def has_value_local(name: String) -> Bool { self.values.contains(name) }
}

pub struct SpecializationOrigin {
    pub let original_id: SymbolId;
    pub let type_args: FrozenVec<TypeId>;
}

pub struct SymbolTable {
    var next_id: i32;
    var next_synthetic_id: i32;
    pub let symbols: Dict<i32, Symbol>;
    pub let builtins: Dict<String, SymbolId>;
    pub let specialization_origin: Dict<i32, SpecializationOrigin>;
    pub let node_to_symbol: Dict<i32, SymbolId>;
    pub let abi_nodes: Dict<i32, String>;
    pub let abi_owners: Dict<i32, String>;
    pub let module_type_keys: Dict<i32, String>;
    pub var separate_modules: Bool;
    let type_index: Dict<String, SymbolId>;

    pub static def new() -> SymbolTable {
        let table = SymbolTable {
            next_id: 0, next_synthetic_id: -1000,
            symbols: Dict<i32, Symbol>.with_capacity(16, 0), builtins: Dict<String, SymbolId>.with_capacity(16, 1), specialization_origin: Dict<i32, SpecializationOrigin>.with_capacity(16, 0),
            node_to_symbol: Dict<i32, SymbolId>.with_capacity(16, 0), type_index: Dict<String, SymbolId>.with_capacity(16, 1),
            abi_nodes: Dict<i32, String>.with_capacity(16, 0), abi_owners: Dict<i32, String>.with_capacity(16, 0),
            module_type_keys: Dict<i32, String>.with_capacity(16, 0), separate_modules: false
        };
        // Allocate builtin protocols before other builtin symbols.
        for name in ["Iterator", "Iterable"] {
            let symbol = table.create_symbol(name, SymbolKind.protocol(), Namespace.type());
            table.builtins[name] = symbol.id;
        }
        for name in ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
                     "f32", "f64", "Bool", "Void", "RawPtr", "Self"] {
            let symbol = table.create_symbol(name, SymbolKind.builtin_type(), Namespace.type());
            table.builtins[name] = symbol.id;
        }
        table
    }

    pub def create_symbol(name: String, kind: SymbolKind, namespace: Namespace,
                          span: Span? = nil, decl_node: NodeId? = nil,
                          is_mutable: Bool = false, visibility: String = "internal") -> Symbol {
        let id = SymbolId { id: self.next_id };
        self.next_id += 1;
        let symbol = Symbol { id, name, kind, namespace, span, decl_node, is_mutable, visibility, is_extension_method: false };
        self.symbols[id.id] = symbol;
        if let node = decl_node { self.node_to_symbol[node.id] = id; }
        if kind.is_indexed_type() { self.type_index[name] = id; }
        symbol
    }
    pub def get_symbol(symbol_id: SymbolId) -> Symbol? { self.symbols[symbol_id.id] }
    pub def get_builtin(name: String) -> SymbolId? { self.builtins[name] }
    pub def get_type_symbol(name: String) -> SymbolId? { self.type_index[name] }
    pub def get_symbol_by_node(node: NodeId) -> SymbolId? { self.node_to_symbol[node.id] }
    pub def create_synthetic_symbol_id() -> SymbolId {
        let result = SymbolId { id: self.next_synthetic_id };
        self.next_synthetic_id -= 1;
        result
    }
    pub def record_specialization(specialized_id: SymbolId, original_id: SymbolId,
                                  type_args: Vec<TypeId>) -> Void {
        self.specialization_origin[specialized_id.id] = SpecializationOrigin {
            original_id, type_args: FrozenVec<TypeId>.new(type_args)
        };
    }
    pub def find_specialization(original_id: SymbolId, type_args: Vec<TypeId>) -> SymbolId? {
        for entry in self.specialization_origin.entries() {
            let origin = entry.value;
            if origin.original_id != original_id || origin.type_args.len() != type_args.len() { continue; }
            var matches = true;
            for i in 0..<type_args.len() {
                if origin.type_args.get(i) != type_args[i] { matches = false; break; }
            }
            if matches { return SymbolId { id: entry.key }; }
        }
        nil
    }
}

pub enum ResolutionErrorKind {
    case undefined_value; case undefined_type; case duplicate_value; case duplicate_type;
    pub def name() -> String {
        switch self {
            case .undefined_value: "UNDEFINED_VALUE";
            case .undefined_type: "UNDEFINED_TYPE";
            case .duplicate_value: "DUPLICATE_VALUE";
            case .duplicate_type: "DUPLICATE_TYPE";
        }
    }
}
pub struct ResolutionError {
    pub var kind: ResolutionErrorKind;
    pub var name: String;
    pub var message: String;
    pub var span: Span? = nil;
    pub def to_string() -> String {
        var location = "";
        if let span = self.span { location = f" at line {span.line}, column {span.column}"; }
        f"{self.kind.name()}: {self.message}{location}"
    }
}

// Named records describe exported symbol and method metadata.
pub struct ExtensionExport {
    pub var type_name: String;
    pub var method_name: String;
    pub var symbol_id: SymbolId;
    pub var visibility: String;
}
pub struct ImportedMethod { pub var name: String; pub var symbol_id: SymbolId; }
pub struct ReExport { pub var name: String; pub var symbol_id: SymbolId; pub var kind: String; }

pub struct ResolutionResult {
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let errors: Vec<ResolutionError>;
    pub let self_symbols: Dict<i32, SymbolId>;
    pub let imported_symbols: Dict<String, SymbolId>;
    pub let extension_methods: Vec<ExtensionExport>;
    pub let imported_extension_methods: Dict<String, Vec<ImportedMethod>>;
    pub let re_exports: Vec<ReExport>;
    pub let re_exported_extension_methods: Vec<ExtensionExport>;

    pub static def new(symbol_table: SymbolTable, node_symbols: Dict<i32, SymbolId>,
                       errors: Vec<ResolutionError>) -> ResolutionResult {
        ResolutionResult { symbol_table, node_symbols, errors, self_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            imported_symbols: Dict<String, SymbolId>.with_capacity(16, 1), extension_methods: Vec<ExtensionExport>.new(), imported_extension_methods: Dict<String, Vec<ImportedMethod>>.with_capacity(16, 1),
            re_exports: Vec<ReExport>.new(), re_exported_extension_methods: Vec<ExtensionExport>.new() }
    }
    pub def has_errors() -> Bool { self.errors.len() != 0 }
    pub def get_symbol_for_node(node: NodeId) -> SymbolId? { self.node_symbols[node.id] }
}
