// Statement checking and control-flow contracts.
pub import "checker_state.rl"
pub struct StmtChecker {
    pub let state: CheckerState;
    pub static def new(state: CheckerState) -> StmtChecker { StmtChecker { state } }
    pub def check_stmt(id: NodeId) -> Void {
        guard let node = self.state.arena.get(id) else { return; }
        switch node.form {
            case .var_decl(let data): self.check_var(id, data);
            case .assignment(let data): self.check_assignment(id, data);
            case .expr_stmt(let data): self.state.infer_expr(data.expr);
            case .return_stmt(let data): self.check_return(id, data);
            case .block: self.state.check_block(id);
            case .if_stmt(let data):
                self.check_condition(data.condition, "if condition");
                self.state.check_block(data.then_block); self.state.check_stmt(data.else_block);
            case .while_stmt(let data):
                if let condition = data.condition { self.state.check_boolean(self.state.infer_expr(condition), "while condition"); }
                self.state.check_block(data.body);
            case .for_stmt(let data):
                if let iterable = data.iterable { self.state.bind_pattern(data.pattern, self.state.iterable_element(self.state.infer_expr(iterable))); }
                self.state.check_block(data.body);
            case .switch_stmt(let data):
                if let value = data.value {
                    let type = self.state.infer_expr(value);
                    for branch in data.cases { self.check_case(branch, type); }
                    self.coverage(id, type);
                }
            case .guard_stmt(let data): self.check_guard(id, data);
            case .defer_stmt(let data): self.state.check_block(data.body);
            default: {}
        }
    }
    pub def coverage(id: NodeId, type: TypeId) -> Void {
        let errors = self.state.result.errors;
        let checker = ExhaustivenessChecker.new(self.state.arena, self.state.type_table, self.state.symbol_table,
            { kind: TypeErrorKind, message: String in errors.push(TypeError { kind, message, span: nil }); });
        checker.check_switch(id, type);
    }
    pub def check_case(id: NodeId, type: TypeId) -> Void {
        if let node = self.state.arena.get(id) {
            switch node.form {
                case .switch_case(let data):
                    for pair in data.patterns {
                        self.state.bind_pattern(pair.0, type);
                        if let condition = pair.1 { self.state.check_boolean(self.state.infer_expr(condition), "case guard"); }
                    }
                    for stmt in data.body { self.state.check_stmt(stmt); }
                default: {}
            }
        }
    }
    def check_condition(condition: AstCondition?, context: String) -> Void {
        if let value = condition {
            switch value {
                case .expression(let id): self.state.check_boolean(self.state.infer_expr(id), context);
                case .binding(let pattern, let expr):
                    let type = self.state.infer_expr(expr);
                    self.state.bind_pattern(pattern, self.state.type_table.get_optional_inner(type) ?? type);
            }
        }
    }
    def check_var(id: NodeId, data: VarDeclAst) -> Void {
        var type: TypeId? = nil;
        if let annotation = data.type_annotation { type = self.state.resolve_type(annotation); }
        if let initializer = data.initializer {
            let init_type = self.state.infer_with_expected(initializer, type);
            if let target = type { self.state.check_assignable(init_type, target, "variable initializer", id); }
            else { type = init_type; }
        }
        if let inferred = type {} else {
            self.state.error(TypeErrorKind.cannot_infer(), "Cannot infer type without initializer or annotation");
            type = self.state.type_table.error_type;
        }
        self.state.bind_pattern(data.pattern, type ?? self.state.type_table.error_type);
    }
    def check_assignment(id: NodeId, data: AssignmentAst) -> Void {
        guard let target = data.target else { return; }
        guard let value = data.value else { return; }
        if let node = self.state.arena.get(target) {
            switch node.form {
                case .identifier:
                    if let symbol_id = self.state.node_symbols[target.id] {
                        if let symbol = self.state.symbol_table.get_symbol(symbol_id) {
                            if !symbol.is_mutable { self.state.error(TypeErrorKind.invalid_operation(), f"cannot reassign immutable binding '{symbol.name}'; use `var` to declare a mutable binding", target); }
                        }
                    }
                default: {}
            }
        }
        let target_type = self.state.infer_expr(target);
        if self.state.lowered_expressions.contains(target.id) {
            if let node = self.state.arena.get(target) {
                switch node.form { case .subscript: self.state.error(TypeErrorKind.invalid_operation(), "slice assignment is not supported; slices are copies", id); return; default: {} }
            }
        }
        let value_type = self.state.infer_expr(value);
        if data.op.equals("=") { self.state.check_assignable(value_type, target_type, "assignment", id); }
        else {
            let op = compound_to_base_op(data.op);
            if let overloaded = self.state.try_operator_overload(nil, target_type, op, value_type) {}
            else { self.state.binary_types(target_type, op, value_type); }
        }
    }
    def check_return(id: NodeId, data: ReturnStmtAst) -> Void {
        if let value = data.value {
            let actual = self.state.infer_with_expected(value, self.state.current_function_return);
            if let expected = self.state.current_function_return { self.state.check_assignable(actual, expected, "return value", id); }
        } else {
            if let expected = self.state.current_function_return {
                if expected != self.state.type_table.void_type { self.state.error(TypeErrorKind.type_mismatch(), f"Function expects return value of type {self.state.type_table.format_type(expected)}", id); }
            }
        }
    }
    def check_guard(id: NodeId, data: GuardStmtAst) -> Void {
        if let condition = data.condition {
            switch condition {
                case .expression(let expr): self.state.check_boolean(self.state.infer_expr(expr), "guard condition");
                case .binding(let pattern, let value):
                    let type = self.state.infer_with_expected(value, nil);
                    var enum_case = false;
                    if let node = self.state.arena.get(pattern) { switch node.form { case .enum_case_pattern: enum_case = true; default: {} } }
                    if let inner = self.state.type_table.get_optional_inner(type) { self.state.bind_pattern(pattern, inner); }
                    else {
                        if !enum_case { self.state.error(TypeErrorKind.type_mismatch(), "guard let requires an optional or an enum case pattern", id); }
                        self.state.bind_pattern(pattern, type);
                    }
            }
        }
        if let body = data.else_block {
            self.state.check_block(body);
            if !self.state.block_diverges(body) { self.state.error(TypeErrorKind.invalid_operation(), "'guard' else block must exit the enclosing scope (e.g. 'return', 'break' or 'continue')"); }
        }
    }
}
