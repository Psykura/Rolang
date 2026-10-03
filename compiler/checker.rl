// Full semantic pipeline. Callback references are scoped to a check to avoid
// retaining an ARC cycle between the shared state and checking components.
pub import "decl_checker.rl"
pub import "stmt_checker.rl"
pub import "expr_checker.rl"
pub struct TypeChecker {
    pub let state: CheckerState;
    let declarations: DeclChecker;
    let statements: StmtChecker;
    let expressions: ExprChecker;
    pub static def new(arena: AstArena, resolution: ResolutionResult) -> TypeChecker {
        let state = CheckerState.new(arena, resolution);
        TypeChecker { state, declarations: DeclChecker.new(state), statements: StmtChecker.new(state), expressions: ExprChecker.new(state) }
    }
    pub def check(program: NodeId) -> TypeCheckResult {
        let expr = self.expressions; let stmt = self.statements; let state = self.state;
        let infer: (NodeId) -> TypeId = (id: NodeId) -> { expr.infer_expr(id) };
        let check: (NodeId) -> Void = (id: NodeId) -> { stmt.check_stmt(id); };
        let contextual: (NodeId, TypeId?) -> TypeId = (id: NodeId, expected: TypeId?) -> { state.infer_with_expected(id, expected) };
        state.infer_callback = infer; state.statement_callback = check;
        state.generic_inference.set_infer_expression(contextual);
        defer { state.infer_callback = nil; state.statement_callback = nil; state.generic_inference.set_infer_expression(nil); }
        self.declarations.run(program);
        self.require_hash_methods(program);
        state.result
    }
    // Dictionaries hash keys with the key type's hash and __eq__ methods, which
    // codegen finds only when instantiated. Methods from generic extensions
    // (Vec's, for instance) are instantiated for every concrete type meeting
    // their where clauses.
    def require_hash_methods(program: NodeId) -> Void {
        let state = self.state;
        let extension_methods = Dict<i32, Bool>.new();
        if let node = state.arena.get(program) { switch node.form { case .program(let data):
            for item in data.items { if let child = state.arena.get(item) { switch child.form {
                case .extension_decl(let extension): if extension.generic_params.len() > 0 { for member in extension.members { extension_methods[member.id] = true; } }
                default: {}
            } } }
            default: {}
        } }
        if extension_methods.len() == 0 { return; }
        for index in 0..<state.type_table.type_count() {
            let type = TypeId { id: index };
            guard let info = state.type_table.get_type(type) else { continue; }
            var arguments = 0;
            switch info.data { case .struct_type(let data): arguments = data.type_args.len(); case .enum_type(let data): arguments = data.type_args.len(); default: continue; }
            if arguments == 0 || state.type_table.has_type_variables(type) { continue; }
            var found = 0; let methods = Vec<SymbolId>.new();
            for name in ["hash", "__eq__"] {
                guard let method = state.member_resolver.get_method(type, name) else { continue; }
                guard let symbol = state.symbol_table.get_symbol(method.symbol_id) else { continue; }
                guard let decl = symbol.decl_node else { continue; }
                if !extension_methods.contains(decl.id) { continue; }
                if !state.method_where_holds(method.symbol_id, state.conformance_checker.type_arguments(type)) { continue; }
                methods.push(method.symbol_id); found += 1;
            }
            if found == 2 { for method in methods { state.result.required_methods.push((type, method)); } }
        }
    }
}
