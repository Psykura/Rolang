// Build the full typed HIR from the checked source arena and semantic side tables.
pub import "hir.rl"
pub import "checker_state.rl"
import std.collections
pub struct HirBuildResult {
    pub let ast: AstArena;
    pub let arena: HirArena;
    pub let program: HirId;
    pub let type_table: TypeTable;
    pub let symbol_table: SymbolTable;
    pub let errors: Vec<String>;
    pub def has_errors() -> Bool { self.errors.len() > 0 }
}
pub struct HirBuilder {
    pub let ast: AstArena;
    pub let arena: HirArena;
    pub let result: TypeCheckResult;
    pub let symbol_table: SymbolTable;
    pub let node_symbols: Dict<i32, SymbolId>;
    pub let type_table: TypeTable;
    pub let type_resolver: TypeResolver;
    pub let errors: Vec<String>;
    var temp_counter: i32;
    // `var` symbols that a closure captures and that are reassigned; they live in a
    // shared __CaptureCell so closures and the enclosing scope see one variable.
    let boxed: Dict<i32, Bool>;
    let cell_types: Dict<i32, TypeId>;
    // Cell declarations for boxed pattern bindings, placed at the start of the binding's scope.
    var pending_cells: Vec<HirId>;
    pub static def new(ast: AstArena, result: TypeCheckResult, symbols: SymbolTable, bindings: Dict<i32, SymbolId>) -> HirBuilder {
        HirBuilder { ast, arena: HirArena.new(), result, symbol_table: symbols, node_symbols: bindings,
            type_table: result.type_table, type_resolver: TypeResolver.new(ast, result.type_table, symbols, bindings), errors: Vec<String>.new(), temp_counter: 0,
            boxed: Dict<i32, Bool>.with_capacity(16, 0), cell_types: Dict<i32, TypeId>.with_capacity(16, 0), pending_cells: Vec<HirId>.new() }
    }
    pub def build(program: NodeId) -> HirBuildResult {
        self.find_boxed_variables(program);
        let items = Vec<HirId>.new();
        if let node = self.ast.get(program) { switch node.form { case .program(let data): for item in data.items { if let built = self.item(item) { items.push(built); } } default: {} } }
        HirBuildResult { ast: self.ast, arena: self.arena, program: self.arena.add(HirForm.program(HirProgramData { items })), type_table: self.type_table, symbol_table: self.symbol_table, errors: self.errors }
    }
    def descendants(root: NodeId) -> Vec<NodeId> {
        let out = Vec<NodeId>.new(); let pending = Vec<NodeId>.new(); pending.push(root);
        while pending.len() > 0 {
            let id = pending.pop();
            if let node = self.ast.get(id) { out.push(id); for child in node.form.children() { pending.push(child); } }
        }
        out
    }
    def find_boxed_variables(program: NodeId) -> Void {
        let mutable = Dict<i32, Bool>.with_capacity(16, 0); let assigned = Dict<i32, Bool>.with_capacity(16, 0); let captured = Dict<i32, Bool>.with_capacity(16, 0);
        for id in self.descendants(program) { if let node = self.ast.get(id) { switch node.form {
            case .var_decl(let data): if data.is_mutable { if let pattern = data.pattern { for child in self.descendants(pattern) {
                if let inner = self.ast.get(child) { switch inner.form { case .identifier_pattern: if let sid = self.node_symbols[child.id] { mutable[sid.id] = true; } default: {} } }
            } } }
            case .identifier_pattern(let data): if let binding = data.binding { if binding.equals("var") { if let sid = self.node_symbols[id.id] { mutable[sid.id] = true; } } }
            case .assignment(let data): if let target = data.target { if let inner = self.ast.get(target) { switch inner.form {
                case .identifier: if let sid = self.node_symbols[target.id] { assigned[sid.id] = true; }
                default: {}
            } } }
            case .lambda:
                let referenced = Dict<i32, Bool>.with_capacity(16, 0); let declared = Dict<i32, Bool>.with_capacity(16, 0);
                for child in self.descendants(id) { if let inner = self.ast.get(child) { switch inner.form {
                    case .identifier: if let sid = self.node_symbols[child.id] { referenced[sid.id] = true; }
                    case .identifier_pattern: if let sid = self.node_symbols[child.id] { declared[sid.id] = true; }
                    default: {}
                } } }
                for entry in referenced.entries() { if !declared.contains(entry.key) { captured[entry.key] = true; } }
            default: {}
        } } }
        for entry in captured.entries() { if mutable.contains(entry.key) && assigned.contains(entry.key) { self.boxed[entry.key] = true; } }
    }
    def take_cells() -> Vec<HirId> {
        let cells = self.pending_cells; self.pending_cells = Vec<HirId>.new(); cells
    }
    def prepend(block: HirId, statements: Vec<HirId>) -> HirId {
        if statements.len() == 0 { return block; }
        if let node = self.arena.get(block) { switch node.form { case .block(let data): for stmt in data.statements { statements.push(stmt); } default: statements.push(block); } }
        self.arena.add(HirForm.block(HirBlockData { statements }))
    }
    // Declares a variable, placing it in a shared cell when it is boxed.
    def declare(name: String, sid: SymbolId, type: TypeId, initializer: HirId?, mutable: Bool) -> HirId {
        if self.boxed.contains(sid.id) { if let symbol = self.symbol_table.get_type_symbol("__CaptureCell") {
            let cell = self.type_table.make_struct(symbol, [type]);
            self.cell_types[sid.id] = cell;
            let statements = Vec<HirId>.new();
            var value: HirId? = initializer;
            if let given = value {} else {
                // A declaration without an initializer starts from the type's default value.
                let temp = self.temp("__default"); let temp_sid = self.temp_symbol(temp);
                statements.push(self.arena.add(HirForm.var_decl(HirVarDeclData { name: temp, symbol_id: temp_sid, type_id: type, initializer: nil, is_mutable: false })));
                value = self.arena.add(HirForm.var_ref(HirVarData { type_id: type, name: temp, symbol_id: temp_sid }));
            }
            let arguments = Vec<(String?, HirId)>.new(); if let content = value { let label: String? = "value"; arguments.push((label, content)); }
            let init = self.arena.add(HirForm.struct_init(HirStructInitData { type_id: cell, struct_type: cell, struct_symbol: symbol, arguments }));
            statements.push(self.arena.add(HirForm.var_decl(HirVarDeclData { name, symbol_id: sid, type_id: cell, initializer: init, is_mutable: false })));
            if statements.len() == 1 { return statements[0]; }
            return self.arena.add(HirForm.block(HirBlockData { statements }));
        } }
        self.arena.add(HirForm.var_decl(HirVarDeclData { name, symbol_id: sid, type_id: type, initializer, is_mutable: mutable }))
    }
    def constant_value(sid: SymbolId) -> NodeId? {
        if let symbol = self.symbol_table.get_symbol(sid) { if let decl = symbol.decl_node { if let node = self.ast.get(decl) { switch node.form { case .constant_decl(let data): return data.value; default: {} } } } }
        nil
    }
    def type_of(id: NodeId?) -> TypeId { if let ref = id { return self.result.expr_types[ref.id] ?? self.type_table.error_type; } self.type_table.error_type }
    def hir_type(id: HirId) -> TypeId { self.arena.type_of(id, self.type_table.error_type) }
    def resolve(id: NodeId?) -> TypeId { self.type_resolver.resolve(id) }
    def return_type(id: NodeId?) -> TypeId { if let ref = id { return self.resolve(ref); } self.type_table.void_type }
    def symbol(id: NodeId, name: String, kind: SymbolKind, space: Namespace, mutable: Bool = false) -> SymbolId {
        self.node_symbols[id.id] ?? self.symbol_table.create_symbol(name, kind, space, nil, nil, mutable).id
    }
    def temp(prefix: String) -> String { self.temp_counter += 1; f"{prefix}_{self.temp_counter}" }
    def temp_symbol(name: String) -> SymbolId { self.symbol_table.create_symbol(name, SymbolKind.variable(), Namespace.value()).id }
    def param_data(id: NodeId) -> ParamAst? { if let node = self.ast.get(id) { switch node.form { case .param(let data): return data; default: {} } } nil }
    def function(id: NodeId?) -> FuncDeclAst? { if let ref = id { if let node = self.ast.get(ref) { switch node.form { case .func_decl(let data): return data; default: {} } } } nil }
    def param(id: NodeId) -> HirId {
        if let data = self.param_data(id) {
            var has_default = false; if let value = data.default_value { has_default = true; }
            return self.arena.add(HirForm.param(HirParamData { name: data.internal_name, symbol_id: self.symbol(id, data.internal_name, SymbolKind.parameter(), Namespace.value()), type_id: self.resolve(data.type_annotation), external_name: data.external_name, has_default }));
        }
        self.arena.add(HirForm.param(HirParamData { name: "__param", symbol_id: SymbolId { id: -1 }, type_id: self.type_table.error_type, external_name: nil, has_default: false }))
    }
    def params(ids: Vec<NodeId>) -> Vec<HirId> { let out = Vec<HirId>.new(); for id in ids { out.push(self.param(id)); } out }
    def build_function(id: NodeId, data: FuncDeclAst, method: Bool) -> HirId {
        let params = self.params(data.params); let ret = self.return_type(data.return_type);
        var body: HirId? = nil; if let ref = data.body { body = self.block(ref); }
        let function = self.arena.add(HirForm.function(HirFunctionData { name: data.name, symbol_id: self.symbol(id, data.name, SymbolKind.function(), Namespace.value()), params, return_type: ret, body, is_async: data.is_async, is_method: method, is_static: data.is_static }));
        self.located(function, id)
    }
    def located(hir: HirId, id: NodeId) -> HirId { self.arena.set_location(hir, self.ast_location(id)); hir }
    def ast_location(id: NodeId) -> HirLocation? {
        guard let node = self.ast.get(id) else { return nil; }
        guard let span = node.span else { return nil; }
        guard let file = self.ast.source_module(id) else { return nil; }
        HirLocation { file, line: span.line, column: span.column }
    }
    def item(id: NodeId) -> HirId? {
        guard let node = self.ast.get(id) else { return nil; }
        switch node.form {
            case .func_decl(let data): return self.build_function(id, data, false);
            case .extern_func_decl(let data): return self.arena.add(HirForm.extern_func(HirExternFuncData { name: data.name, symbol_id: self.symbol(id, data.name, SymbolKind.extern_func(), Namespace.value()), abi: data.abi, params: self.params(data.params), return_type: self.return_type(data.return_type) }));
            case .struct_decl(let data):
                let fields = Vec<HirId>.new(); let methods = Vec<HirId>.new();
                for member in data.members { if let child = self.ast.get(member) { switch child.form {
                    case .property_decl(let prop):
                        var value: HirId? = nil; if let ref = prop.initializer { value = self.expr(ref); }
                        fields.push(self.arena.add(HirForm.field(HirFieldData { name: prop.name, symbol_id: self.symbol(member, prop.name, SymbolKind.variable(), Namespace.value()), type_id: self.resolve(prop.type_annotation), is_mutable: prop.is_mutable, default_value: value })));
                    case .func_decl(let func): methods.push(self.build_function(member, func, true));
                    default: {}
                } } }
                return self.arena.add(HirForm.struct_type(HirStructData { name: data.name, symbol_id: self.symbol(id, data.name, SymbolKind.struct_type(), Namespace.type()), fields, methods }));
            case .enum_decl(let data):
                let cases = Vec<HirId>.new(); let methods = Vec<HirId>.new();
                for member in data.members { if let child = self.ast.get(member) { switch child.form {
                    case .enum_case_decl(let group): for case_id in group.cases { if let case_node = self.ast.get(case_id) { switch case_node.form { case .enum_case_def(let value):
                        let payload = Vec<(String?, TypeId)>.new(); for pair in value.payload { payload.push((pair.0, self.resolve(pair.1))); }
                        cases.push(self.arena.add(HirForm.enum_case(HirEnumCaseData { name: value.name, symbol_id: self.symbol(case_id, value.name, SymbolKind.enum_case(), Namespace.value()), payload })));
                        default: {}
                    } } }
                    case .func_decl(let func): methods.push(self.build_function(member, func, true));
                    default: {}
                } } }
                return self.arena.add(HirForm.enum_type(HirEnumData { name: data.name, symbol_id: self.symbol(id, data.name, SymbolKind.enum_type(), Namespace.type()), cases, methods }));
            case .protocol_decl(let data):
                let funcs = Vec<HirId>.new(); let props = Vec<HirId>.new();
                for member in data.members { if let child = self.ast.get(member) { switch child.form {
                    case .protocol_func_req(let req):
                        let params = Vec<(String?, TypeId)>.new(); for p in req.params { if let param = self.param_data(p) { params.push((param.external_name, self.resolve(param.type_annotation))); } }
                        funcs.push(self.arena.add(HirForm.func_requirement(HirFuncRequirementData { name: req.name, params, return_type: self.return_type(req.return_type), is_async: req.is_async })));
                    case .protocol_prop_req(let req): props.push(self.arena.add(HirForm.prop_requirement(HirPropRequirementData { name: req.name, type_id: self.resolve(req.type_annotation), has_getter: req.has_getter, has_setter: req.has_setter })));
                    default: {}
                } } }
                return self.arena.add(HirForm.protocol(HirProtocolData { name: data.name, symbol_id: self.symbol(id, data.name, SymbolKind.protocol(), Namespace.type()), func_requirements: funcs, prop_requirements: props }));
            case .extension_decl(let data):
                let extended_type = self.resolve(data.extended_type);
                let methods = Vec<HirId>.new(); for member in data.members { if let func = self.function(member) { methods.push(self.build_function(member, func, true)); } }
                return self.arena.add(HirForm.extension(HirExtensionData { extended_type, methods }));
            case .import_decl | .type_alias_decl | .constant_decl: return nil;
            default: if node.form.category().name().equals("statement") { self.errors.push("Top-level statements are not supported"); }
        }
        nil
    }
    def empty_block() -> HirId { self.arena.add(HirForm.block(HirBlockData { statements: Vec<HirId>.new() })) }
    def statements(ids: Vec<NodeId>, demote_tail: Bool = false) -> HirId {
        let out = Vec<HirId>.new();
        for index in 0..<ids.len() {
            let id = ids[index]; var demoted = false;
            if demote_tail && index == ids.len() - 1 { if let node = self.ast.get(id) { switch node.form { case .return_stmt(let data): if data.implicit { if let ref = data.value { out.push(self.arena.add(HirForm.expr_stmt(HirExprStmtData { expr: self.expr(ref) }))); demoted = true; } } default: {} } } }
            if !demoted { out.push(self.stmt(id)); }
            self.arena.set_location(out[out.len() - 1], self.ast_location(id));
        }
        self.arena.add(HirForm.block(HirBlockData { statements: out }))
    }
    def block(id: NodeId?, demote_tail: Bool = false) -> HirId {
        if let ref = id { if let node = self.ast.get(ref) { switch node.form { case .block(let data): return self.statements(data.statements, demote_tail); default: {} } } }
        self.empty_block()
    }
    def else_branch(id: NodeId?) -> HirId? {
        if let ref = id { let built = self.stmt(ref); if let node = self.arena.get(built) { switch node.form { case .if_let: let items = Vec<HirId>.new(); items.push(built); return self.arena.add(HirForm.block(HirBlockData { statements: items })); default: {} } } return built; } nil
    }
    def conditional(condition: AstCondition?, then_body: NodeId?, else_body: NodeId?) -> HirId {
        if let cond = condition { switch cond {
            case .binding(let pattern, let value):
                let type = self.type_of(value); let bound = self.type_table.get_optional_inner(type) ?? type;
                let p = self.pattern(pattern, bound); let cells = self.take_cells(); let scrutinee = self.expr(value);
                let then_block = self.prepend(self.block(then_body), cells); let else_block = self.else_branch(else_body);
                return self.arena.add(HirForm.if_let(HirIfLetData { pattern: p, scrutinee, then_block, else_block }));
            case .expression(let value):
                let c = self.expr(value); let then_block = self.block(then_body); let else_block = self.else_branch(else_body);
                return self.arena.add(HirForm.if_stmt(HirIfData { condition: c, then_block, else_block }));
        } }
        self.arena.add(HirForm.if_stmt(HirIfData { condition: self.error_expr(), then_block: self.block(then_body), else_block: self.else_branch(else_body) }))
    }
    def stmt(id: NodeId) -> HirId {
        guard let node = self.ast.get(id) else { return self.empty_block(); }
        switch node.form {
            case .block: return self.block(id);
            case .var_decl(let data): return self.var_decl(data);
            case .assignment(let data):
                if let lowered = self.result.lowered_expressions[id.id] { return self.arena.add(HirForm.expr_stmt(HirExprStmtData { expr: self.expr(lowered) })); }
                var op: String? = nil; if !data.op.equals("=") { op = compound_to_base_op(data.op); }
                return self.arena.add(HirForm.assign(HirAssignData { target: self.expr(data.target), value: self.expr(data.value), compound_op: op }));
            case .expr_stmt(let data): return self.arena.add(HirForm.expr_stmt(HirExprStmtData { expr: self.expr(data.expr) }));
            case .return_stmt(let data): var value: HirId? = nil; if let ref = data.value { value = self.expr(ref); } return self.arena.add(HirForm.return_stmt(HirReturnData { value }));
            case .break_stmt: return self.arena.add(HirForm.break_stmt());
            case .continue_stmt: return self.arena.add(HirForm.continue_stmt());
            case .if_stmt(let data): return self.conditional(data.condition, data.then_block, data.else_block);
            case .guard_stmt(let data):
                if let cond = data.condition { switch cond {
                    case .binding: return self.conditional(data.condition, nil, data.else_block);
                    case .expression(let ref): return self.arena.add(HirForm.guard_stmt(HirGuardData { condition: self.expr(ref), else_block: self.block(data.else_block) }));
                } }
                return self.arena.add(HirForm.guard_stmt(HirGuardData { condition: self.error_expr(), else_block: self.block(data.else_block) }));
            case .while_stmt(let data): return self.arena.add(HirForm.while_stmt(HirWhileData { condition: self.expr(data.condition), body: self.block(data.body, true) }));
            case .for_stmt(let data):
                let iterable = self.expr(data.iterable); let p = self.pattern(data.pattern, self.result.loop_element_types[id.id] ?? self.iterable_element(self.type_of(data.iterable)));
                let cells = self.take_cells();
                return self.arena.add(HirForm.for_stmt(HirForData { pattern: p, iterable, body: self.prepend(self.block(data.body, true), cells) }));
            case .switch_stmt(let data): return self.switch_stmt(data.value, data.cases);
            case .defer_stmt(let data): return self.arena.add(HirForm.defer_stmt(HirDeferData { body: self.block(data.body) }));
            default: self.errors.push(internal_compiler_error("HIR lowering does not handle statement " + node.form.kind())); return self.empty_block();
        }
    }
    def var_decl(data: VarDeclAst) -> HirId {
        var type = self.type_of(data.initializer); if let annotation = data.type_annotation { type = self.resolve(annotation); }
        if let ref = data.pattern { if let node = self.ast.get(ref) { switch node.form { case .identifier_pattern(let p):
            let sid = self.symbol(ref, p.name, SymbolKind.variable(), Namespace.value(), data.is_mutable);
            var initializer: HirId? = nil; if let value = data.initializer { initializer = self.expr(value); }
            return self.declare(p.name, sid, type, initializer, data.is_mutable);
            default: {}
        } } }
        let sid = self.temp_symbol("__pattern"); var initializer: HirId? = nil; if let value = data.initializer { initializer = self.expr(value); }
        let statements = Vec<HirId>.new(); statements.push(self.arena.add(HirForm.var_decl(HirVarDeclData { name: "__pattern", symbol_id: sid, type_id: type, initializer, is_mutable: false })));
        self.project_bindings(data.pattern, self.arena.add(HirForm.var_ref(HirVarData { type_id: type, name: "__pattern", symbol_id: sid })), statements, data.is_mutable);
        self.arena.add(HirForm.block(HirBlockData { statements }))
    }
    def project_bindings(id: NodeId?, value: HirId, out: Vec<HirId>, mutable: Bool) -> Void {
        if let ref = id { if let node = self.ast.get(ref) { switch node.form {
            case .identifier_pattern(let p): out.push(self.declare(p.name, self.node_symbols[ref.id] ?? SymbolId { id: -1 }, self.hir_type(value), value, mutable));
            case .tuple_pattern(let data):
                if let info = self.type_table.get_type(self.hir_type(value)) { switch info.data { case .struct_type(let tuple): if let fields = tuple.anon_fields {
                    for index in 0..<data.elements.len() { if index < fields.len() { let field = fields.get(index); let child = self.arena.add(HirForm.field_access(HirFieldAccessData { type_id: field.type_id, object: value, field_name: field.name, field_symbol: nil })); self.project_bindings(data.elements[index].1, child, out, mutable); } }
                    } default: {}
                } }
            default: {}
        } } }
    }
    def switch_stmt(value: NodeId?, cases: Vec<NodeId>) -> HirId {
        let scrutinee = self.expr(value); let type = self.type_of(value); let branches = Vec<HirId>.new();
        for branch in cases { branches.push(self.switch_case(branch, type)); }
        self.arena.add(HirForm.switch_stmt(HirSwitchData { scrutinee, scrutinee_type: type, cases: branches }))
    }
    def switch_case(id: NodeId, type: TypeId) -> HirId {
        let patterns = Vec<(HirId, HirId?)>.new(); var body = self.empty_block(); var is_default = false;
        if let node = self.ast.get(id) { switch node.form { case .switch_case(let data):
            for pair in data.patterns { let p = self.pattern(pair.0, type); var c: HirId? = nil; if let ref = pair.1 { c = self.expr(ref); } patterns.push((p, c)); }
            let cells = self.take_cells();
            body = self.prepend(self.statements(data.body), cells); is_default = data.is_default;
            default: {}
        } }
        self.arena.add(HirForm.switch_case(HirSwitchCaseData { patterns, body, is_default }))
    }
    def error_expr() -> HirId { self.arena.add(HirForm.literal(HirLiteralData { type_id: self.type_table.error_type, value: HirValue.none(), kind: "nil" })) }
    def literal_value(value: LiteralValue) -> HirValue {
        switch value { case .integer(let data): HirValue.integer(data); case .floating(let data): HirValue.floating(data); case .boolean(let data): HirValue.boolean(data); case .text(let data): HirValue.text(data); case .none: HirValue.none(); }
    }
    def expr(id: NodeId?) -> HirId {
        guard let ref = id else { return self.error_expr(); }
        guard let node = self.ast.get(ref) else { return self.error_expr(); }
        let type_id = self.type_of(ref);
        switch node.form {
            case .literal(let data):
                var value = self.literal_value(data.value);
                // An integer literal typed by a floating-point context becomes a floating constant.
                if self.type_table.is_float(type_id) { switch value { case .integer(let text): value = HirValue.floating(text.to_f64()); default: {} } }
                return self.arena.add(HirForm.literal(HirLiteralData { type_id, value, kind: data.kind }));
            case .identifier(let data):
                let sid = self.symbol(ref, data.name, SymbolKind.variable(), Namespace.value());
                // A module-level constant is its value expression, inlined at each use.
                if let constant = self.constant_value(sid) { return self.expr(constant); }
                if let cell = self.cell_types[sid.id] {
                    let holder = self.arena.add(HirForm.var_ref(HirVarData { type_id: cell, name: data.name, symbol_id: sid }));
                    return self.arena.add(HirForm.field_access(HirFieldAccessData { type_id, object: holder, field_name: "value", field_symbol: nil }));
                }
                return self.arena.add(HirForm.var_ref(HirVarData { type_id, name: data.name, symbol_id: sid }));
            case .type_reference(let data):
                var sid = SymbolId { id: -1 }; var name = "<type>";
                if let info = self.type_table.get_type(type_id) { switch info.data { case .struct_type(let value): sid = value.symbol_id ?? sid; case .enum_type(let value): sid = value.symbol_id; default: {} } }
                if let syntax = data.type_name { if let child = self.ast.get(syntax) { switch child.form { case .named_type(let value): name = value.name; case .builtin_type(let value): name = value.name; default: {} } } }
                return self.arena.add(HirForm.var_ref(HirVarData { type_id, name, symbol_id: sid }));
            case .binary_op(let data):
                if let lowered = self.result.lowered_expressions[ref.id] { return self.expr(lowered); }
                if data.op.equals("??") { return self.coalesce(data, type_id); }
                let left = self.expr(data.left); let right = self.expr(data.right);
                if data.op.equals("==") || data.op.equals("!=") {
                    var value: HirId? = nil;
                    if self.hir_type(right) == self.type_table.nil_type { value = left; } else if self.hir_type(left) == self.type_table.nil_type { value = right; }
                    if let optional = value { if let inner = self.type_table.get_optional_inner(self.hir_type(optional)) { return self.presence_test(optional, inner, data.op.equals("!=")); } }
                }
                if self.result.optional_comparisons.contains(ref.id) { return self.optional_comparison(ref, data.op, left, right); }
                if let target = self.result.operator_targets[ref.id] {
                    let args = Vec<(String?, HirId)>.new(); let label: String? = nil; args.push((label, right));
                    var name = to_method_name(data.op); if name.is_empty() { name = data.op; }
                    return self.arena.add(HirForm.method_call(HirMethodCallData { type_id, receiver: left, method_name: name, arguments: args, method_symbol: target.symbol_id, is_static: false }));
                }
                return self.arena.add(HirForm.binary_op(HirBinaryOpData { type_id, left, op: data.op, right }));
            case .unary_op(let data):
                let operand = self.expr(data.operand);
                if let target = self.result.operator_targets[ref.id] {
                    return self.arena.add(HirForm.method_call(HirMethodCallData { type_id, receiver: operand, method_name: to_unary_method_name(data.op), arguments: Vec<(String?, HirId)>.new(), method_symbol: target.symbol_id, is_static: false }));
                }
                if data.op.equals("+") { return operand; }
                if data.op.equals("try") { return self.arena.add(HirForm.try_expr(HirTryExprData { type_id, expr: operand, result_type: type_id, error_type: self.result.propagation_error_types[ref.id] })); }
                return self.arena.add(HirForm.unary_op(HirUnaryOpData { type_id, op: data.op, operand }));
            case .ternary_op(let data): return self.arena.add(HirForm.ternary(HirTernaryData { type_id, condition: self.expr(data.condition), then_expr: self.expr(data.then_expr), else_expr: self.expr(data.else_expr) }));
            case .call(let data): return self.call(ref, data);
            case .member_access(let data):
                if let lowered = self.result.lowered_expressions[ref.id] { return self.expr(lowered); }
                return self.member(ref, data);
            case .optional_chain(let data): return self.optional_chain(ref, data, type_id);
            case .subscript(let data):
                if let lowered = self.result.lowered_expressions[ref.id] { return self.expr(lowered); }
                let object = self.expr(data.object); let indices = Vec<HirId>.new(); for index in data.indices { indices.push(self.expr(index)); }
                return self.arena.add(HirForm.subscript(HirSubscriptData { type_id, object, indices }));
            case .tuple_expr(let data):
                let elements = Vec<(String?, HirId)>.new(); for pair in data.elements { elements.push((pair.0, self.expr(pair.1))); }
                return self.arena.add(HirForm.tuple(HirTupleData { type_id, elements }));
            case .array_literal(let data):
                let elements = Vec<HirId>.new(); for element in data.elements { elements.push(self.expr(element)); }
                var element_type = self.type_table.error_type;
                if let info = self.type_table.get_type(type_id) { switch info.data { case .struct_type(let value): if value.type_args.len() > 0 { element_type = value.type_args.get(0); } default: {} } }
                return self.arena.add(HirForm.array(HirArrayData { type_id, elements, element_type }));
            case .dict_literal(let data):
                let entries = Vec<(HirId, HirId)>.new(); for pair in data.entries { entries.push((self.expr(pair.0), self.expr(pair.1))); }
                var key_type = self.type_table.error_type; var value_type = self.type_table.error_type;
                if let info = self.type_table.get_type(type_id) { switch info.data { case .struct_type(let value): if value.type_args.len() >= 2 { key_type = value.type_args.get(0); value_type = value.type_args.get(1); } default: {} } }
                return self.arena.add(HirForm.dict(HirDictData { type_id, entries, key_type, value_type }));
            case .lambda(let data):
                let params = Vec<HirId>.new(); let signature = self.type_table.get_function_data(type_id);
                let destructure = Vec<HirId>.new();
                for index in 0..<data.params.len() {
                    let pair = data.params[index]; var param_type = self.type_table.error_type; if let func = signature { if index < func.params.len() { param_type = func.params.get(index); } }
                    var name: String? = nil; if let child = self.ast.get(pair.0) { switch child.form { case .identifier_pattern(let p): name = p.name; default: {} } }
                    if let simple = name {
                        params.push(self.arena.add(HirForm.param(HirParamData { name: simple, symbol_id: self.symbol(pair.0, simple, SymbolKind.parameter(), Namespace.value()), type_id: param_type, external_name: nil, has_default: false })));
                    } else {
                        // A pattern parameter such as `(a, b)` binds its components at the start of the body.
                        let temp = self.temp("__param"); let sid = self.temp_symbol(temp);
                        params.push(self.arena.add(HirForm.param(HirParamData { name: temp, symbol_id: sid, type_id: param_type, external_name: nil, has_default: false })));
                        self.project_bindings(pair.0, self.arena.add(HirForm.var_ref(HirVarData { type_id: param_type, name: temp, symbol_id: sid })), destructure, false);
                    }
                }
                var body = self.statements(data.body);
                if destructure.len() > 0 { if let node = self.arena.get(body) { switch node.form { case .block(let block): for stmt in block.statements { destructure.push(stmt); } body = self.arena.add(HirForm.block(HirBlockData { statements: destructure })); default: {} } } }
                return self.located(self.arena.add(HirForm.lambda(HirLambdaData { type_id, params, body, captures: Vec<SymbolId>.new() })), ref);
            case .struct_literal(let data):
                var sid = SymbolId { id: -1 }; if let info = self.type_table.get_type(type_id) { switch info.data { case .struct_type(let value): sid = value.symbol_id ?? sid; default: {} } }
                let arguments = self.arguments(data.arguments);
                // Omitted fields take their declared default values, evaluated per literal.
                if let symbol = self.symbol_table.get_symbol(sid) { if let decl = symbol.decl_node { if let node = self.ast.get(decl) { switch node.form { case .struct_decl(let decl_data):
                    for member in decl_data.members { if let child = self.ast.get(member) { switch child.form { case .property_decl(let prop): if let initial = prop.initializer {
                        var given = false; for pair in arguments { if let label = pair.0 { if label.equals(prop.name) { given = true; } } }
                        if !given { let label: String? = prop.name; arguments.push((label, self.expr(initial))); }
                    } default: {} } } }
                    default: {}
                } } } }
                return self.arena.add(HirForm.struct_init(HirStructInitData { type_id, struct_type: type_id, struct_symbol: sid, arguments }));
            case .cast(let data): return self.arena.add(HirForm.cast(HirCastData { type_id, expr: self.expr(data.expr), target_type: self.resolve(data.target_type), kind: data.kind }));
            case .type_check(let data): return self.arena.add(HirForm.type_check(HirTypeCheckData { type_id, expr: self.expr(data.expr), checked_type: self.resolve(data.checked_type) }));
            case .try_expr(let data): return self.arena.add(HirForm.try_expr(HirTryExprData { type_id, expr: self.expr(data.value), result_type: type_id, error_type: self.result.propagation_error_types[ref.id] }));
            case .size_of_expr: return self.intrinsic(ref, type_id, "size_of");
            case .type_id_expr: return self.intrinsic(ref, type_id, "type_id");
            case .align_of_expr: return self.intrinsic(ref, type_id, "align_of");
            case .drop_of_expr | .clone_of_expr: return self.arena.add(HirForm.literal(HirLiteralData { type_id, value: HirValue.boolean((self.result.intrinsic_values[ref.id] ?? 0) != 0), kind: "bool" }));
            case .switch_expr(let data):
                let name = self.temp("__switch_value"); let sid = self.temp_symbol(name);
                let switch_id = self.switch_stmt(data.value, data.cases);
                if let built = self.arena.get(switch_id) { switch built.form { case .switch_stmt(let switch_data):
                    for branch in switch_data.cases { if let child = self.arena.get(branch) { switch child.form { case .switch_case(let case_data): if let block = self.arena.get(case_data.body) { switch block.form { case .block(let body): if body.statements.len() > 0 { if let first = self.arena.get(body.statements[0]) { switch first.form { case .expr_stmt(let expr):
                        let target = self.arena.add(HirForm.var_ref(HirVarData { type_id, name, symbol_id: sid }));
                        let statements = Vec<HirId>.new(); statements.push(self.arena.add(HirForm.assign(HirAssignData { target, value: expr.expr, compound_op: nil })));
                        case_data.body = self.arena.add(HirForm.block(HirBlockData { statements }));
                        default: {}
                    } } } default: {} } } default: {} } } }
                    default: {}
                } }
                return self.arena.add(HirForm.switch_expr(HirSwitchExprData { type_id, switch: switch_id, result_symbol: sid }));
            default: self.errors.push(internal_compiler_error("HIR lowering does not handle expression " + node.form.kind())); return self.error_expr();
        }
    }
    def arguments(ids: Vec<NodeId>) -> Vec<(String?, HirId)> {
        let out = Vec<(String?, HirId)>.new();
        for id in ids { if let node = self.ast.get(id) { switch node.form { case .argument(let data): out.push((data.label, self.expr(data.value))); default: {} } } }
        out
    }
    def defaults(args: Vec<(String?, HirId)>, sid: SymbolId?) -> Vec<(String?, HirId)> {
        if let symbol_id = sid { if let sym = self.symbol_table.get_symbol(symbol_id) { if let ref = sym.decl_node { if let node = self.ast.get(ref) {
            var params = Vec<NodeId>.new(); switch node.form { case .func_decl(let data): params = data.params; case .extern_func_decl(let data): params = data.params; default: return args; }
            for index in args.len()..<params.len() { if let param = self.param_data(params[index]) { if let value = param.default_value { args.push((param.external_name, self.expr(value))); } else { break; } } }
        } } } }
        args
    }
    def member(id: NodeId, data: MemberAccessAst) -> HirId {
        let type_id = self.type_of(id);
        if let target = self.result.call_targets[id.id] { switch target.kind { case .enum_ctor: return self.arena.add(HirForm.enum_construct(HirEnumConstructData { type_id, enum_type: type_id, case_name: target.case_name ?? data.member, case_symbol: nil, payload: Vec<(String?, HirId)>.new() })); default: {} } }
        self.arena.add(HirForm.field_access(HirFieldAccessData { type_id, object: self.expr(data.object), field_name: data.member, field_symbol: nil }))
    }
    def call(id: NodeId, data: CallAst) -> HirId {
        let type_id = self.type_of(id); var arguments = self.arguments(data.arguments);
        let target = self.result.call_targets[id.id];
        if let t = target { switch t.kind { case .enum_ctor: return self.arena.add(HirForm.enum_construct(HirEnumConstructData { type_id, enum_type: type_id, case_name: t.case_name ?? "", case_symbol: nil, payload: arguments })); default: {} } }
        var callee = self.expr(data.callee);
        if let ref = data.callee {
            if let access = self.result.call_targets[ref.id] { switch access.kind { case .indirect: return self.arena.add(HirForm.call(HirCallData { type_id, callee, arguments, callee_symbol: nil })); default: {} } }
            if let node = self.ast.get(ref) { switch node.form { case .member_access(let member):
                if let sid = self.node_symbols[ref.id] {
                    callee = self.arena.add(HirForm.var_ref(HirVarData { type_id: self.type_of(ref), name: member.member, symbol_id: sid }));
                    arguments = self.defaults(arguments, sid);
                    return self.arena.add(HirForm.call(HirCallData { type_id, callee, arguments, callee_symbol: sid }));
                }
                let receiver = self.expr(member.object);
                if let inner = self.type_table.get_optional_inner(self.hir_type(receiver)) {
                    if member.member.equals("is_some") || member.member.equals("is_none") || member.member.equals("unwrap_or") {
                        let bool_type = self.type_table.get_builtin("Bool") ?? self.type_table.error_type;
                        let name = self.temp("__opt_" + member.member); let sid = self.temp_symbol(name);
                        var some: HirId; var none: HirId; var type = bool_type;
                        if member.member.equals("unwrap_or") { type = inner; some = self.arena.add(HirForm.var_ref(HirVarData { type_id: inner, name, symbol_id: sid })); if arguments.len() > 0 { none = arguments[0].1; } else { none = self.error_expr(); } }
                        else { return self.presence_test(receiver, inner, member.member.equals("is_some")); }
                        return self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: type, scrutinee: receiver, inner_type: inner, some_binding: sid, some_expr: some, none_expr: none }));
                    }
                }
                let method_symbol = self.result.member_method_symbols[ref.id]; arguments = self.defaults(arguments, method_symbol);
                var is_static = false; if let sid = method_symbol { if let sym = self.symbol_table.get_symbol(sid) { if let func = self.function(sym.decl_node) { is_static = func.is_static; } } }
                if member.member.equals("clone") && !is_static && arguments.len() == 0 && self.type_table.is_heap_type(type_id) { return self.arena.add(HirForm.clone(HirCloneData { type_id, value: receiver })); }
                return self.arena.add(HirForm.method_call(HirMethodCallData { type_id, receiver, method_name: member.member, arguments, method_symbol, is_static }));
                default: {}
            } }
        }
        var callee_symbol: SymbolId? = nil; if let t = target { callee_symbol = t.symbol_id; }
        arguments = self.defaults(arguments, callee_symbol);
        self.arena.add(HirForm.call(HirCallData { type_id, callee, arguments, callee_symbol }))
    }
    def intrinsic(id: NodeId, type_id: TypeId, kind: String) -> HirId {
        if let target = self.result.intrinsic_types[id.id] { if kind.equals("type_id") || self.type_table.has_type_variables(target) { return self.arena.add(HirForm.literal(HirLiteralData { type_id, value: HirValue.type_id(target), kind })); } }
        var fallback: i64 = 0; if kind.equals("align_of") { fallback = 8; }
        self.arena.add(HirForm.literal(HirLiteralData { type_id, value: HirValue.integer((self.result.intrinsic_values[id.id] ?? fallback).to_string()), kind: "int" }))
    }
    def coalesce(data: BinaryOpAst, type: TypeId) -> HirId {
        let scrutinee = self.expr(data.left); let inner = self.type_table.get_optional_inner(self.hir_type(scrutinee)) ?? self.hir_type(scrutinee);
        let name = self.temp("__coal"); let sid = self.temp_symbol(name);
        let some = self.arena.add(HirForm.var_ref(HirVarData { type_id: inner, name, symbol_id: sid })); let none = self.expr(data.right);
        self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: type, scrutinee, inner_type: inner, some_binding: sid, some_expr: some, none_expr: none }))
    }
    // `a == b` with an optional operand: both nil, or both present with equal values. A
    // non-optional operand is wrapped; each operand is evaluated once, left to right.
    def optional_comparison(id: NodeId, op: String, left: HirId, right: HirId) -> HirId {
        let bool_type = self.type_table.get_builtin("Bool") ?? self.type_table.error_type;
        let lhs = self.as_optional(left); let rhs = self.as_optional(right);
        let left_inner = self.type_table.get_optional_inner(self.hir_type(lhs)) ?? self.hir_type(left);
        let right_inner = self.type_table.get_optional_inner(self.hir_type(rhs)) ?? self.hir_type(right);
        let x = self.temp("__lhs"); let x_sid = self.temp_symbol(x); let y = self.temp("__rhs"); let y_sid = self.temp_symbol(y);
        let x_ref = self.arena.add(HirForm.var_ref(HirVarData { type_id: left_inner, name: x, symbol_id: x_sid }));
        let y_ref = self.arena.add(HirForm.var_ref(HirVarData { type_id: right_inner, name: y, symbol_id: y_sid }));
        var values = self.arena.add(HirForm.binary_op(HirBinaryOpData { type_id: bool_type, left: x_ref, op, right: y_ref }));
        if let target = self.result.operator_targets[id.id] {
            let args = Vec<(String?, HirId)>.new(); let label: String? = nil; args.push((label, y_ref));
            values = self.arena.add(HirForm.method_call(HirMethodCallData { type_id: bool_type, receiver: x_ref, method_name: to_method_name(op), arguments: args, method_symbol: target.symbol_id, is_static: false }));
        }
        let differ = op.equals("!=");
        let unequal = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(differ), kind: "bool" }));
        let equal = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(!differ), kind: "bool" }));
        let unused = self.temp_symbol(self.temp("__rhs"));
        // The right operand appears in both branches of the left match; exactly one runs.
        let when_left = self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: rhs, inner_type: right_inner, some_binding: y_sid, some_expr: values, none_expr: unequal }));
        let when_nil = self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: rhs, inner_type: right_inner, some_binding: unused, some_expr: unequal, none_expr: equal }));
        self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: lhs, inner_type: left_inner, some_binding: x_sid, some_expr: when_left, none_expr: when_nil }))
    }
    def as_optional(value: HirId) -> HirId {
        let type = self.hir_type(value);
        if self.type_table.is_optional(type) { return value; }
        self.arena.add(HirForm.optional_some(HirOptionalSomeData { type_id: self.type_table.make_optional(type), value, inner_type: type }))
    }
    // Bool that is `present` when the optional holds a value and `!present` when it is nil.
    def presence_test(optional: HirId, inner: TypeId, present: Bool) -> HirId {
        let bool_type = self.type_table.get_builtin("Bool") ?? self.type_table.error_type;
        let sid = self.temp_symbol(self.temp("__opt_present"));
        let some = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(present), kind: "bool" }));
        let none = self.arena.add(HirForm.literal(HirLiteralData { type_id: bool_type, value: HirValue.boolean(!present), kind: "bool" }));
        self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: bool_type, scrutinee: optional, inner_type: inner, some_binding: sid, some_expr: some, none_expr: none }))
    }
    // The checker rewrites field, call and subscript chains to an ordinary expression whose
    // receiver is the `__opt_chain` binding of the unwrapped object.
    def chain_binding(content: NodeId) -> NodeId? {
        guard let node = self.ast.get(content) else { return nil; }
        var member: NodeId? = nil;
        switch node.form { case .member_access: member = content; case .call(let data): member = data.callee; case .subscript(let data): member = data.object; default: {} }
        if let ref = member { if let child = self.ast.get(ref) { switch child.form {
            case .member_access(let access): return access.object;
            // `object?[index]`: the subscript's object is the binding itself.
            case .identifier: return ref;
            default: {}
        } } }
        nil
    }
    def optional_chain(id: NodeId, data: OptionalChainAst, type: TypeId) -> HirId {
        let scrutinee = self.expr(data.object); let inner = self.type_table.get_optional_inner(self.hir_type(scrutinee)) ?? self.hir_type(scrutinee);
        if let lowered = self.result.lowered_expressions[id.id] { if let holder = self.chain_binding(lowered) { if let sid = self.node_symbols[holder.id] {
            let content = self.expr(lowered); let content_type = self.hir_type(content);
            // An optional member value is already the chain result.
            var some = content;
            if content_type != type { some = self.arena.add(HirForm.optional_some(HirOptionalSomeData { type_id: type, value: content, inner_type: content_type })); }
            let none = self.arena.add(HirForm.optional_none(HirOptionalNoneData { type_id: type, inner_type: self.type_table.get_optional_inner(type) ?? content_type }));
            return self.arena.add(HirForm.optional_match(HirOptionalMatchData { type_id: type, scrutinee, inner_type: inner, some_binding: sid, some_expr: some, none_expr: none }));
        } } }
        // The checker lowers every valid chain; anything else has already been reported.
        self.error_expr()
    }
    def pattern(id: NodeId?, expected: TypeId) -> HirId {
        if let ref = id { if let node = self.ast.get(ref) { switch node.form {
            case .identifier_pattern(let data):
                var mutable = false; if let binding = data.binding { mutable = binding.equals("var"); }
                let sid = self.symbol(ref, data.name, SymbolKind.variable(), Namespace.value(), mutable);
                if self.boxed.contains(sid.id) {
                    // Bind a temporary; the enclosing scope starts by moving it into the variable's cell.
                    let temp = self.temp("__bound"); let temp_sid = self.temp_symbol(temp);
                    self.pending_cells.push(self.declare(data.name, sid, expected, self.arena.add(HirForm.var_ref(HirVarData { type_id: expected, name: temp, symbol_id: temp_sid })), false));
                    return self.arena.add(HirForm.binding_pattern(HirBindingPatternData { name: temp, symbol_id: temp_sid, type_id: expected, is_mutable: false }));
                }
                return self.arena.add(HirForm.binding_pattern(HirBindingPatternData { name: data.name, symbol_id: sid, type_id: expected, is_mutable: mutable }));
            case .literal_pattern(let data):
                if let value = data.value { if let child = self.ast.get(value) { switch child.form { case .literal(let lit): return self.arena.add(HirForm.literal_pattern(HirLiteralPatternData { value: self.literal_value(lit.value), type_id: expected })); default: {} } } }
            case .tuple_pattern(let data):
                let elements = Vec<(String?, HirId)>.new(); var fields = FrozenVec<TupleField>.empty();
                if let info = self.type_table.get_type(expected) { switch info.data { case .struct_type(let value): if let sid = value.symbol_id {} else { fields = value.anon_fields ?? fields; } default: {} } }
                for index in 0..<data.elements.len() { let pair = data.elements[index]; var type = self.type_table.error_type; if index < fields.len() { type = fields.get(index).type_id; } elements.push((pair.0, self.pattern(pair.1, type))); }
                return self.arena.add(HirForm.tuple_pattern(HirTuplePatternData { elements, type_id: expected }));
            case .enum_case_pattern(let data):
                let types = self.enum_payloads(expected, data.case_name); let payload = Vec<HirId>.new();
                for index in 0..<data.payload.len() { var type = self.type_table.error_type; if index < types.len() { type = types[index]; } payload.push(self.pattern(data.payload[index], type)); }
                return self.arena.add(HirForm.enum_case_pattern(HirEnumCasePatternData { case_name: data.case_name, case_symbol: nil, payload, enum_type: expected }));
            case .typed_pattern(let data): var type = expected; if let ann = data.type_annotation { type = self.resolve(ann); } return self.pattern(data.pattern, type);
            case .or_pattern(let data): let patterns = Vec<HirId>.new(); for p in data.patterns { patterns.push(self.pattern(p, expected)); } return self.arena.add(HirForm.or_pattern(HirOrPatternData { patterns, type_id: expected }));
            default: {}
        } } }
        self.arena.add(HirForm.wildcard_pattern())
    }
    def enum_payloads(type: TypeId, name: String) -> Vec<TypeId> {
        let out = Vec<TypeId>.new();
        if let inner = self.type_table.get_optional_inner(type) { if name.equals("Some") { out.push(inner); } return out; }
        if let info = self.type_table.get_type(type) { switch info.data { case .enum_type(let data):
            if let sym = self.symbol_table.get_symbol(data.symbol_id) { if let ref = sym.decl_node { if let node = self.ast.get(ref) { switch node.form { case .enum_decl(let decl):
                let subst = Dict<String, TypeId>.with_capacity(16, 1);
                if data.type_args.len() == decl.generic_params.len() { for index in 0..<decl.generic_params.len() { if let param = self.ast.get(decl.generic_params[index]) { switch param.form { case .generic_param(let p): subst[p.name] = data.type_args.get(index); default: {} } } } }
                for member in decl.members { if let child = self.ast.get(member) { switch child.form { case .enum_case_decl(let group): for case_id in group.cases { if let case_node = self.ast.get(case_id) { switch case_node.form { case .enum_case_def(let value): if value.name.equals(name) { for pair in value.payload { out.push(self.substitute(self.resolve(pair.1), subst)); } return out; } default: {} } } } default: {} } } }
                default: {}
            } } } }
            default: {}
        } }
        out
    }
    def substitute(type: TypeId, subst: Dict<String, TypeId>) -> TypeId {
        if subst.len() == 0 { return type; }
        if let info = self.type_table.get_type(type) { switch info.data {
            case .type_variable(let data): return subst[data.name] ?? (self.type_table.project(data.name, subst) ?? type);
            case .struct_type(let data):
                if let sid = data.symbol_id { let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.substitute(arg, subst)); } return self.type_table.make_struct(sid, args); }
                let fields = Vec<(String?, TypeId)>.new(); if let elements = data.anon_fields { for field in elements { let label: String? = field.name; fields.push((label, self.substitute(field.type_id, subst))); } } return self.type_table.make_tuple(fields);
            case .enum_type(let data): let args = Vec<TypeId>.new(); for arg in data.type_args { args.push(self.substitute(arg, subst)); } return self.type_table.make_enum(data.symbol_id, args);
            case .optional(let inner): return self.type_table.make_optional(self.substitute(inner, subst));
            default: {}
        } }
        type
    }
    def iterable_element(type: TypeId) -> TypeId {
        if let info = self.type_table.get_type(type) { switch info.data { case .struct_type(let data): if let sid = data.symbol_id { if let sym = self.symbol_table.get_symbol(sid) { if (sym.name.equals("Vec") || sym.name.starts_with("Vec_") || sym.name.equals("Dict") || sym.name.starts_with("Dict_")) && data.type_args.len() > 0 { return data.type_args.get(0); } } } default: {} } }
        if let sid = self.symbol_table.get_builtin("Iterable") {
            let protocol = self.type_table.get_protocol_type(sid);
            let conformance = ConformanceChecker.new(self.ast, self.type_table, self.symbol_table);
            if conformance.check_conformance(type, protocol).conforms {
                let members = MemberResolver.new(self.ast, self.type_table, self.symbol_table);
                if let iter = members.get_method(type, "__iter__") { if let func = self.type_table.get_function_data(iter.signature) { if let next = members.get_method(func.return_type, "__next__") { if let n = self.type_table.get_function_data(next.signature) { return self.type_table.get_optional_inner(n.return_type) ?? self.type_table.error_type; } } } }
            }
        }
        self.type_table.error_type
    }
}
