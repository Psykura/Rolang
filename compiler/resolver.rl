// Two-pass name resolution. Every binding uses arena-owned NodeIds.
pub import "module.rl"
import std.path
import std.collections

pub struct NameResolver {
    pub let arena: AstArena;
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let errors: Vec<ResolutionError>;
    pub let self_symbols: Dict<i32, SymbolId>;
    pub let imported_symbols: Dict<String, SymbolId>;
    pub let extension_methods: Vec<ExtensionExport>;
    pub let imported_extension_methods: Dict<String, Vec<ImportedMethod>>;
    pub let re_exports: Vec<ReExport>;
    pub let re_exported_extension_methods: Vec<ExtensionExport>;
    let module_graph: ModuleGraph?;
    let current_module: Module?;
    let import_targets: Dict<i32, String>;
    var current_scope: Scope? = nil;
    var current_type_symbol: SymbolId? = nil;

    pub static def new(arena: AstArena, symbol_table: SymbolTable? = nil,
                       node_symbols: Dict<i32, SymbolId>? = nil,
                       module_graph: ModuleGraph? = nil, current_module: Module? = nil,
                       import_targets: Dict<i32, String>? = nil) -> NameResolver {
        NameResolver {
            arena, symbol_table: symbol_table ?? SymbolTable.new(),
            node_symbols: node_symbols ?? Dict<i32, SymbolId>.with_capacity(16, 0),
            errors: Vec<ResolutionError>.new(), self_symbols: Dict<i32, SymbolId>.with_capacity(16, 0),
            imported_symbols: Dict<String, SymbolId>.with_capacity(16, 1),
            extension_methods: Vec<ExtensionExport>.new(),
            imported_extension_methods: Dict<String, Vec<ImportedMethod>>.with_capacity(16, 1),
            re_exports: Vec<ReExport>.new(), re_exported_extension_methods: Vec<ExtensionExport>.new(),
            module_graph, current_module, import_targets: import_targets ?? Dict<i32, String>.with_capacity(16, 0),
            current_scope: nil, current_type_symbol: nil
        }
    }
    pub def resolve(program: NodeId) -> ResolutionResult {
        self.push_scope(ScopeKind.module());
        if let scope = self.current_scope {
            for item in self.symbol_table.builtins.entries() { scope.define_type(item.key, item.value); }
        }
        if let node = self.arena.get(program) {
            switch node.form {
                case .program(let data):
                    for item in data.items { self.resolve_import(item); }
                    for item in data.items { self.collect_item(item); }
                    for item in data.items { self.resolve_item(item); }
                default: {}
            }
        }
        self.pop_scope();
        ResolutionResult {
            symbol_table: self.symbol_table, node_symbols: self.node_symbols, errors: self.errors,
            self_symbols: self.self_symbols, imported_symbols: self.imported_symbols,
            extension_methods: self.extension_methods, imported_extension_methods: self.imported_extension_methods,
            re_exports: self.re_exports, re_exported_extension_methods: self.re_exported_extension_methods
        }
    }
    def push_scope(kind: ScopeKind) -> Void { self.current_scope = Scope.new(kind, self.current_scope); }
    def pop_scope() -> Void { if let scope = self.current_scope { self.current_scope = scope.parent; } }
    def span(id: NodeId?) -> Span? {
        if let value = id { if let node = self.arena.get(value) { return node.span; } }
        nil
    }
    def error(kind: ResolutionErrorKind, name: String, message: String, id: NodeId? = nil) -> Void {
        self.errors.push(ResolutionError { kind, name, message, span: self.span(id) });
    }
    def define_type(name: String, kind: SymbolKind, id: NodeId,
                    visibility: String = "internal") -> Symbol? {
        guard let scope = self.current_scope else { return nil; }
        if scope.has_type_local(name) {
            self.error(ResolutionErrorKind.duplicate_type(), name, f"Type '{name}' is already defined in this scope", id);
            return nil;
        }
        let symbol = self.symbol_table.create_symbol(name, kind, Namespace.type(), self.span(id), id, false, visibility);
        scope.define_type(name, symbol.id);
        self.node_symbols[id.id] = symbol.id;
        symbol
    }
    def define_value(name: String, kind: SymbolKind, id: NodeId? = nil,
                     mutable: Bool = false, visibility: String = "internal") -> Symbol? {
        guard let scope = self.current_scope else { return nil; }
        if scope.has_value_local(name) {
            self.error(ResolutionErrorKind.duplicate_value(), name, f"'{name}' is already defined in this scope", id);
            return nil;
        }
        let symbol = self.symbol_table.create_symbol(name, kind, Namespace.value(), self.span(id), id, mutable, visibility);
        scope.define_value(name, symbol.id);
        if let node = id { self.node_symbols[node.id] = symbol.id; }
        symbol
    }
    def lookup_type(name: String, id: NodeId) -> SymbolId? {
        guard let scope = self.current_scope else { return nil; }
        if let symbol = scope.lookup_type(name) { self.node_symbols[id.id] = symbol; return symbol; }
        if let symbol = self.imported_symbols[name] { self.node_symbols[id.id] = symbol; return symbol; }
        self.error(ResolutionErrorKind.undefined_type(), name, f"Undefined type '{name}'", id);
        nil
    }
    def lookup_value(name: String, id: NodeId) -> Void {
        guard let scope = self.current_scope else { return; }
        if let symbol = scope.lookup_value(name) { self.node_symbols[id.id] = symbol; return; }
        if let symbol = self.imported_symbols[name] { self.node_symbols[id.id] = symbol; return; }
        if let symbol = scope.lookup_type(name) { self.node_symbols[id.id] = symbol; return; }
        self.error(ResolutionErrorKind.undefined_value(), name, f"Undefined variable or function '{name}'", id);
    }
    def collect_item(id: NodeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .struct_decl(let data): self.define_type(data.name, SymbolKind.struct_type(), id, data.visibility);
            case .enum_decl(let data): self.define_type(data.name, SymbolKind.enum_type(), id, data.visibility);
            case .protocol_decl(let data): self.define_type(data.name, SymbolKind.protocol(), id, data.visibility);
            case .type_alias_decl(let data): self.define_type(data.name, SymbolKind.type_alias(), id, data.visibility);
            case .func_decl(let data): self.define_value(data.name, SymbolKind.function(), id, false, data.visibility);
            case .extern_func_decl(let data): self.define_value(data.name, SymbolKind.extern_func(), id, false, data.visibility);
            default: {}
        }
    }
    def resolve_item(id: NodeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .struct_decl(let data): self.resolve_type_body(data.name, data.generic_params, data.constraints, data.members, true);
            case .enum_decl(let data): self.resolve_type_body(data.name, data.generic_params, data.constraints, data.members, false);
            case .protocol_decl(let data):
                self.push_scope(ScopeKind.type());
                self.resolve_generics(data.generic_params);
                self.resolve_constraints(data.constraints, data.generic_params);
                for member in data.members { self.resolve_protocol_member(member); }
                self.pop_scope();
            case .type_alias_decl(let data):
                self.push_scope(ScopeKind.type()); self.resolve_generics(data.generic_params);
                self.resolve_type(data.aliased_type); self.pop_scope();
            case .func_decl(let data): self.resolve_function(id, data);
            case .extern_func_decl(let data):
                self.push_scope(ScopeKind.function());
                self.resolve_generics(data.generic_params); self.resolve_constraints(data.constraints, data.generic_params);
                for param in data.params { self.resolve_param_type(param); }
                self.resolve_type(data.return_type); self.pop_scope();
            case .extension_decl(let data): self.resolve_extension(id, data);
            default: {}
        }
    }
    def resolve_generics(params: Vec<NodeId>) -> Void {
        for id in params {
            if let node = self.arena.get(id) {
                switch node.form {
                    case .generic_param(let data):
                        self.define_type(data.name, SymbolKind.generic_param(), id);
                        if let bounds = data.bounds { for bound in bounds { self.resolve_type(bound); } }
                    default: {}
                }
            }
        }
    }
    def resolve_constraints(constraints: Vec<NodeId>, params: Vec<NodeId>) -> Void {
        for id in constraints {
            guard let node = self.arena.get(id) else { continue; }
            switch node.form {
                case .constraint(let data):
                    var subject_name = "";
                    if let subject = data.subject {
                        switch subject {
                            case .type_ref(let ref):
                                self.resolve_type(ref);
                                if let target = self.arena.get(ref) {
                                    switch target.form { case .named_type(let named): subject_name = named.name; default: {} }
                                }
                            case .name(let name): subject_name = name;
                        }
                    }
                    if data.kind.equals("conforms") {
                        for bound in data.bounds { self.resolve_type(bound); }
                        for param in params {
                            guard let param_node = self.arena.get(param) else { continue; }
                            switch param_node.form {
                                case .generic_param(let generic):
                                    if generic.name.equals(subject_name) {
                                        let bounds = generic.bounds ?? Vec<NodeId>.new();
                                        for bound in data.bounds {
                                            // A where-bound at a different source position remains a distinct AST node.
                                            var found = false;
                                            for previous in bounds { if previous == bound { found = true; } }
                                            if !found { bounds.push(bound); }
                                        }
                                        generic.bounds = bounds;
                                        break;
                                    }
                                default: {}
                            }
                        }
                    } else if data.kind.equals("equals") { self.resolve_type(data.equal_type); }
                default: {}
            }
        }
    }
    def resolve_type_body(name: String, generics: Vec<NodeId>, constraints: Vec<NodeId>,
                          members: Vec<NodeId>, properties: Bool) -> Void {
        self.push_scope(ScopeKind.type());
        var type_symbol: SymbolId? = nil;
        if let scope = self.current_scope { if let parent = scope.parent { type_symbol = parent.lookup_type(name); } }
        self.resolve_generics(generics); self.resolve_constraints(constraints, generics);
        if properties {
            for id in members {
                if let node = self.arena.get(id) {
                    switch node.form {
                        case .property_decl(let data): self.define_value(data.name, SymbolKind.field(), id, data.is_mutable);
                        default: {}
                    }
                }
            }
        }
        let old = self.current_type_symbol; self.current_type_symbol = type_symbol;
        for id in members {
            guard let node = self.arena.get(id) else { continue; }
            switch node.form {
                case .enum_case_decl(let data):
                    for case_id in data.cases {
                        if let case_node = self.arena.get(case_id) {
                            switch case_node.form {
                                case .enum_case_def(let item): for payload in item.payload { self.resolve_type(payload.1); }
                                default: {}
                            }
                        }
                    }
                default: self.resolve_member(id);
            }
        }
        self.current_type_symbol = old; self.pop_scope();
    }
    def resolve_member(id: NodeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .property_decl(let data): self.resolve_type(data.type_annotation); self.resolve_expr(data.initializer);
            case .func_decl(let data):
                self.define_value(data.name, SymbolKind.function(), id); self.resolve_function(id, data);
            default: {}
        }
    }
    def resolve_protocol_member(id: NodeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .protocol_func_req(let data):
                self.push_scope(ScopeKind.function()); self.resolve_generics(data.generic_params);
                for param in data.params { self.resolve_param_type(param); }
                self.resolve_type(data.return_type); self.pop_scope();
            case .protocol_prop_req(let data): self.resolve_type(data.type_annotation);
            case .associated_type_decl(let data):
                self.define_type(data.name, SymbolKind.associated_type(), id);
                self.resolve_constraints(data.constraints, Vec<NodeId>.new());
            default: {}
        }
    }
    def resolve_extension(id: NodeId, data: ExtensionDeclAst) -> Void {
        var name = "";
        if let ref = data.extended_type {
            if let node = self.arena.get(ref) {
                switch node.form { case .named_type(let target): name = target.name; default: {} }
            }
        }
        var symbol_name = "<extension>";
        if name.len() > 0 { symbol_name = f"<extension:{name}>"; }
        let symbol = self.symbol_table.create_symbol(symbol_name, SymbolKind.extension(), Namespace.type(), nil, id);
        self.node_symbols[id.id] = symbol.id;
        self.push_scope(ScopeKind.type()); self.resolve_generics(data.generic_params);
        self.resolve_type(data.extended_type);
        var type_symbol: SymbolId? = nil;
        if let ref = data.extended_type { type_symbol = self.node_symbols[ref.id]; }
        if let found = type_symbol {} else {
            if let scope = self.current_scope { type_symbol = scope.lookup_type(name); }
        }
        for ref in data.conformances { self.resolve_type(ref); }
        self.resolve_constraints(data.constraints, Vec<NodeId>.new());
        let old = self.current_type_symbol; self.current_type_symbol = type_symbol;
        let methods = Vec<SymbolId>.new();
        for member in data.members {
            self.resolve_member(member);
            if let node = self.arena.get(member) {
                switch node.form {
                    case .func_decl(let method):
                        if let scope = self.current_scope { if let sid = scope.lookup_value(method.name) { methods.push(sid); } }
                    default: {}
                }
            }
        }
        self.current_type_symbol = old; self.pop_scope();
        for sid in methods {
            if let method = self.symbol_table.get_symbol(sid) {
                method.is_extension_method = true;
                if !data.visibility.equals("internal") { method.visibility = data.visibility; }
                self.extension_methods.push(ExtensionExport {
                    type_name: name, method_name: method.name, symbol_id: sid, visibility: data.visibility
                });
            }
        }
    }
    def resolve_function(id: NodeId, data: FuncDeclAst) -> Void {
        self.push_scope(ScopeKind.function());
        self.resolve_generics(data.generic_params); self.resolve_constraints(data.constraints, data.generic_params);
        for param in data.params {
            if let node = self.arena.get(param) {
                switch node.form { case .param(let p): self.resolve_expr(p.default_value); default: {} }
            }
        }
        if let enclosing_type = self.current_type_symbol {
            if !data.is_static {
                if let receiver = self.define_value("self", SymbolKind.parameter()) {
                    if let function = self.node_symbols[id.id] { self.self_symbols[function.id] = receiver.id; }
                }
            }
        }
        for param in data.params {
            self.resolve_param_type(param);
            if let node = self.arena.get(param) {
                switch node.form { case .param(let p): self.define_value(p.internal_name, SymbolKind.parameter(), param); default: {} }
            }
        }
        self.resolve_type(data.return_type); self.resolve_block(data.body); self.pop_scope();
    }
    def resolve_param_type(id: NodeId) -> Void {
        if let node = self.arena.get(id) {
            switch node.form { case .param(let data): self.resolve_type(data.type_annotation); default: {} }
        }
    }
    def resolve_type(id: NodeId?) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .builtin_type(let data): self.lookup_type(data.name, ref);
            case .named_type(let data):
                var name = data.name;
                if data.module_path.len() > 0 { name = join_strings(data.module_path, ".") + "." + name; }
                self.lookup_type(name, ref);
                for arg in data.generic_args { self.resolve_type(arg); }
            case .pointer_type: {}
            default: for child in node.form.children() { self.resolve_type(child); }
        }
    }
    def resolve_block(id: NodeId?) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .block(let data):
                self.push_scope(ScopeKind.block());
                for stmt in data.statements { self.resolve_stmt(stmt); }
                self.pop_scope();
            default: {}
        }
    }
    def block_items(id: NodeId?) -> Vec<NodeId> {
        if let ref = id {
            if let node = self.arena.get(ref) {
                switch node.form { case .block(let data): return data.statements; default: {} }
            }
        }
        Vec<NodeId>.new()
    }
    def resolve_stmt(id: NodeId) -> Void {
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .var_decl(let data):
                self.resolve_type(data.type_annotation); self.resolve_expr(data.initializer);
                self.bind_pattern(data.pattern, data.is_mutable);
            case .assignment(let data): self.resolve_expr(data.target); self.resolve_expr(data.value);
            case .expr_stmt(let data): self.resolve_expr(data.expr);
            case .return_stmt(let data): self.resolve_expr(data.value);
            case .block(_): self.resolve_block(id);
            case .if_stmt(let data):
                var bound = false;
                if let condition = data.condition {
                    switch condition {
                        case .expression(let expr): self.resolve_expr(expr);
                        case .binding(let pattern, let expr):
                            self.resolve_expr(expr); self.push_scope(ScopeKind.block());
                            self.bind_pattern(pattern, false);
                            for stmt in self.block_items(data.then_block) { self.resolve_stmt(stmt); }
                            self.pop_scope(); bound = true;
                    }
                }
                if !bound { self.resolve_block(data.then_block); }
                if let otherwise = data.else_block { self.resolve_stmt(otherwise); }
            case .guard_stmt(let data):
                if let condition = data.condition {
                    switch condition {
                        case .expression(let expr): self.resolve_expr(expr); self.resolve_block(data.else_block);
                        case .binding(let pattern, let expr):
                            self.resolve_expr(expr); self.resolve_block(data.else_block); self.bind_pattern(pattern, false);
                    }
                } else { self.resolve_block(data.else_block); }
            case .while_stmt(let data): self.resolve_expr(data.condition); self.resolve_block(data.body);
            case .for_stmt(let data):
                self.resolve_expr(data.iterable); self.push_scope(ScopeKind.for_loop());
                self.bind_pattern(data.pattern, false);
                for stmt in self.block_items(data.body) { self.resolve_stmt(stmt); }
                self.pop_scope();
            case .switch_stmt(let data): self.resolve_switch(data.value, data.cases);
            case .defer_stmt(let data): self.resolve_block(data.body);
            default: {}
        }
    }
    def resolve_switch(value: NodeId?, cases: Vec<NodeId>) -> Void {
        self.resolve_expr(value);
        for ref in cases {
            guard let node = self.arena.get(ref) else { continue; }
            switch node.form {
                case .switch_case(let data):
                    self.push_scope(ScopeKind.switch_case());
                    for pair in data.patterns { self.bind_pattern(pair.0, false); self.resolve_expr(pair.1); }
                    for stmt in data.body { self.resolve_stmt(stmt); }
                    self.pop_scope();
                default: {}
            }
        }
    }
    def bind_pattern(id: NodeId?, mutable: Bool) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .identifier_pattern(let data):
                self.define_value(data.name, SymbolKind.variable(), ref, mutable || (data.binding ?? "").equals("var"));
            case .tuple_pattern(let data): for pair in data.elements { self.bind_pattern(pair.1, mutable); }
            case .enum_case_pattern(let data): for pattern in data.payload { self.bind_pattern(pattern, mutable); }
            case .typed_pattern(let data): self.resolve_type(data.type_annotation); self.bind_pattern(data.pattern, mutable);
            case .or_pattern(let data): if data.patterns.len() > 0 { self.bind_pattern(data.patterns[0], mutable); }
            default: {}
        }
    }
    def member_name(id: NodeId) -> String? {
        guard let node = self.arena.get(id) else { return nil; }
        switch node.form {
            case .identifier(let data): return data.name;
            case .member_access(let data):
                if let object = data.object {
                    if let prefix = self.member_name(object) { return prefix + "." + data.member; }
                }
            default: {}
        }
        nil
    }
    def resolve_expr(id: NodeId?) -> Void {
        guard let ref = id else { return; }
        guard let node = self.arena.get(ref) else { return; }
        switch node.form {
            case .identifier(let data): self.lookup_value(data.name, ref);
            case .type_reference(let data): self.resolve_type(data.type_name);
            case .member_access(let data):
                if let name = self.member_name(ref) {
                    if let symbol = self.imported_symbols[name] { self.node_symbols[ref.id] = symbol; return; }
                }
                self.resolve_expr(data.object);
            case .optional_chain(let data):
                self.resolve_expr(data.object);
                if let suffix = data.suffix {
                    switch suffix {
                        case .call(let args):
                            for arg in args {
                                if let arg_node = self.arena.get(arg) {
                                    switch arg_node.form { case .argument(let a): self.resolve_expr(a.value); default: {} }
                                }
                            }
                        case .index(let indices): for index in indices { self.resolve_expr(index); }
                    }
                }
            case .lambda(let data):
                self.push_scope(ScopeKind.lambda());
                for pair in data.params { self.resolve_type(pair.1); self.bind_pattern(pair.0, false); }
                self.resolve_type(data.return_type);
                for stmt in data.body { self.resolve_stmt(stmt); }
                self.pop_scope();
            case .struct_literal(let data):
                self.resolve_type(data.type_name); for arg in data.arguments { self.resolve_expr(arg); }
            case .cast(let data): self.resolve_expr(data.expr); self.resolve_type(data.target_type);
            case .type_check(let data): self.resolve_expr(data.expr); self.resolve_type(data.checked_type);
            case .size_of_expr(let data): self.resolve_type(data.type_arg);
            case .type_id_expr(let data): self.resolve_type(data.type_arg);
            case .align_of_expr(let data): self.resolve_type(data.type_arg);
            case .drop_of_expr(let data): self.resolve_type(data.type_arg);
            case .clone_of_expr(let data): self.resolve_type(data.type_arg);
            case .switch_expr(let data): self.resolve_switch(data.value, data.cases);
            default: for child in node.form.children() { self.resolve_expr(child); }
        }
    }
    def validate_alias(alias: String, id: NodeId) -> Bool {
        switch alias {
            case "def", "let", "var", "if", "else", "while", "for", "return", "import",
                 "as", "in", "where", "struct", "enum", "protocol", "typealias", "extension",
                 "extern", "init", "deinit", "self", "Self", "pub", "private", "internal",
                 "async", "await", "try", "throws", "true", "false", "nil", "is", "switch",
                 "case", "default", "guard", "defer", "break", "continue":
                self.error(ResolutionErrorKind.duplicate_value(), alias, f"import alias '{alias}' is a reserved word", id);
                return false;
            default: {}
        }
        if self.symbol_table.builtins.contains(alias) {
            self.error(ResolutionErrorKind.duplicate_type(), alias, f"import alias '{alias}' shadows a built-in type", id);
            return false;
        }
        if let scope = self.current_scope {
            if scope.has_value_local(alias) || scope.has_type_local(alias) {
                self.error(ResolutionErrorKind.duplicate_value(), alias, f"import alias '{alias}' is already defined in this scope", id);
                return false;
            }
        }
        true
    }
    def resolve_import(id: NodeId) -> Void {
        guard let graph = self.module_graph else { return; }
        guard let current = self.current_module else { return; }
        guard let node = self.arena.get(id) else { return; }
        switch node.form {
            case .import_decl(let data):
                if data.path.len() == 0 { return; }
                if let alias = data.alias { if !self.validate_alias(alias, id) { return; } }
                var target: Module? = nil;
                if let name = self.import_targets[id.id] { target = graph.get_module(name); }
                else {
                    let resolved = path_resolve(path_join(path_dirname(current.path), data.path));
                    for module in graph.modules.values() {
                        if path_basename(module.path).equals(data.path) || module.path.equals(data.path) ||
                           module.path.ends_with("/" + data.path) || module.path.ends_with("\\" + data.path) ||
                           path_resolve(module.path).equals(resolved) { target = module; break; }
                    }
                }
                guard let imported = target else {
                    self.error(ResolutionErrorKind.undefined_type(), data.path, f"Module not found: '{data.path}'", id);
                    return;
                }
                for export in imported.exports.values() {
                    if !export.visibility.equals("pub") { continue; }
                    var name = export.name;
                    if let alias = data.alias { name = alias + "." + name; }
                    self.imported_symbols[name] = export.symbol_id;
                    if data.visibility.equals("pub") {
                        self.re_exports.push(ReExport { name, symbol_id: export.symbol_id, kind: export.kind });
                    }
                }
                for method in imported.extension_exports {
                    if !method.visibility.equals("pub") { continue; }
                    let methods = self.imported_extension_methods[method.type_name] ?? Vec<ImportedMethod>.new();
                    methods.push(ImportedMethod { name: method.method_name, symbol_id: method.symbol_id });
                    self.imported_extension_methods[method.type_name] = methods;
                    if data.visibility.equals("pub") { self.re_exported_extension_methods.push(method); }
                }
            default: {}
        }
    }
}

pub def resolve_names(arena: AstArena, program: NodeId) -> ResolutionResult {
    NameResolver.new(arena).resolve(program)
}

pub def resolve_with_modules(arena: AstArena, program: NodeId, graph: ModuleGraph,
                             current: Module, symbols: SymbolTable? = nil,
                             node_symbols: Dict<i32, SymbolId>? = nil) -> ResolutionResult {
    NameResolver.new(arena, symbols, node_symbols, graph, current).resolve(program)
}
