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
        state.result
    }
}
