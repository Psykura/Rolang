// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "ids.rl"

// Literal payloads preserve integers as decimal text until semantic checking.
pub enum LiteralValue { case integer(String); case floating(f64); case boolean(Bool); case text(String); case none; }
pub enum AstCondition { case expression(NodeId); case binding(NodeId, NodeId); }
pub enum AstOptionalSuffix { case call(Vec<NodeId>); case index(Vec<NodeId>); }
pub enum AstConstraintSubject { case type_ref(NodeId); case name(String); }
pub enum NodeCategory {
    case program; case type_syntax; case pattern; case expression; case statement; case declaration; case auxiliary;
    pub def name() -> String {
        switch self {
            case .program: "program"; case .type_syntax: "type_syntax";
            case .pattern: "pattern"; case .expression: "expression";
            case .statement: "statement"; case .declaration: "declaration";
            case .auxiliary: "auxiliary";
        }
    }
}

pub struct ProgramAst {
    pub var items: Vec<NodeId>;
}
pub struct BuiltinTypeAst {
    pub var name: String;
}
pub struct NamedTypeAst {
    pub var name: String;
    pub var module_path: Vec<String>;
    pub var generic_args: Vec<NodeId>;
}
pub struct OptionalTypeAst {
    pub var inner: NodeId?;
}
pub struct ArrayTypeAst {
    pub var element: NodeId?;
}
pub struct DictTypeAst {
    pub var key: NodeId?;
    pub var value: NodeId?;
}
pub struct TupleTypeAst {
    pub var elements: Vec<(String?, NodeId)>;
}
pub struct FunctionTypeAst {
    pub var params: Vec<NodeId>;
    pub var return_type: NodeId?;
    pub var is_async: Bool;
}
pub struct AnyTypeAst {
    pub var protocol: NodeId?;
}
pub struct IdentifierPatternAst {
    pub var name: String;
    pub var binding: String?;
}
pub struct LiteralPatternAst {
    pub var value: NodeId?;
}
pub struct TuplePatternAst {
    pub var elements: Vec<(String?, NodeId)>;
}
pub struct EnumCasePatternAst {
    pub var case_name: String;
    pub var payload: Vec<NodeId>;
}
pub struct TypedPatternAst {
    pub var pattern: NodeId?;
    pub var type_annotation: NodeId?;
}
pub struct OrPatternAst {
    pub var patterns: Vec<NodeId>;
}
pub struct LiteralAst {
    pub var value: LiteralValue;
    pub var kind: String;
}
pub struct IdentifierAst {
    pub var name: String;
}
pub struct TypeReferenceAst {
    pub var type_name: NodeId?;
}
pub struct BinaryOpAst {
    pub var left: NodeId?;
    pub var op: String;
    pub var right: NodeId?;
}
pub struct UnaryOpAst {
    pub var op: String;
    pub var operand: NodeId?;
}
pub struct TernaryOpAst {
    pub var condition: NodeId?;
    pub var then_expr: NodeId?;
    pub var else_expr: NodeId?;
}
pub struct ArgumentAst {
    pub var label: String?;
    pub var value: NodeId?;
}
pub struct CallAst {
    pub var callee: NodeId?;
    pub var arguments: Vec<NodeId>;
    pub var is_interpolation: Bool;
}
pub struct TryExprAst {
    pub var value: NodeId?;
}
pub struct MemberAccessAst {
    pub var object: NodeId?;
    pub var member: String;
}
pub struct OptionalChainAst {
    pub var object: NodeId?;
    pub var member: String;
    pub var suffix: AstOptionalSuffix?;
}
pub struct SubscriptAst {
    pub var object: NodeId?;
    pub var indices: Vec<NodeId>;
}
pub struct TupleExprAst {
    pub var elements: Vec<(String?, NodeId)>;
}
pub struct ArrayLiteralAst {
    pub var elements: Vec<NodeId>;
}
pub struct DictLiteralAst {
    pub var entries: Vec<(NodeId, NodeId)>;
}
pub struct LambdaAst {
    pub var params: Vec<(NodeId, NodeId?)>;
    pub var body: Vec<NodeId>;
    pub var return_type: NodeId?;
}
pub struct StructLiteralAst {
    pub var type_name: NodeId?;
    pub var arguments: Vec<NodeId>;
}
pub struct SizeOfExprAst {
    pub var type_arg: NodeId?;
}
pub struct TypeIdExprAst {
    pub var type_arg: NodeId?;
}
pub struct AlignOfExprAst {
    pub var type_arg: NodeId?;
}
pub struct DropOfExprAst {
    pub var type_arg: NodeId?;
}
pub struct CloneOfExprAst {
    pub var type_arg: NodeId?;
}
pub struct CastAst {
    pub var expr: NodeId?;
    pub var target_type: NodeId?;
    pub var kind: String;
}
pub struct TypeCheckAst {
    pub var expr: NodeId?;
    pub var checked_type: NodeId?;
}
pub struct VarDeclAst {
    pub var pattern: NodeId?;
    pub var type_annotation: NodeId?;
    pub var initializer: NodeId?;
    pub var is_mutable: Bool;
}
pub struct AssignmentAst {
    pub var target: NodeId?;
    pub var op: String;
    pub var value: NodeId?;
}
pub struct ExprStmtAst {
    pub var expr: NodeId?;
}
pub struct ReturnStmtAst {
    pub var value: NodeId?;
    pub var implicit: Bool;
}
pub struct BlockAst {
    pub var statements: Vec<NodeId>;
    pub var is_unsafe: Bool;
}
pub struct IfStmtAst {
    pub var condition: AstCondition?;
    pub var then_block: NodeId?;
    pub var else_block: NodeId?;
}
pub struct GuardStmtAst {
    pub var condition: AstCondition?;
    pub var else_block: NodeId?;
}
pub struct WhileStmtAst {
    pub var condition: NodeId?;
    pub var body: NodeId?;
}
pub struct ForStmtAst {
    pub var pattern: NodeId?;
    pub var iterable: NodeId?;
    pub var body: NodeId?;
}
pub struct SwitchCaseAst {
    pub var patterns: Vec<(NodeId, NodeId?)>;
    pub var body: Vec<NodeId>;
    pub var is_default: Bool;
}
pub struct SwitchStmtAst {
    pub var value: NodeId?;
    pub var cases: Vec<NodeId>;
}
pub struct SwitchExprAst {
    pub var value: NodeId?;
    pub var cases: Vec<NodeId>;
}
pub struct DeferStmtAst {
    pub var body: NodeId?;
}
pub struct GenericParamAst {
    pub var name: String;
    pub var bounds: Vec<NodeId>?;
}
pub struct ConstraintAst {
    pub var subject: AstConstraintSubject?;
    pub var kind: String;
    pub var bounds: Vec<NodeId>;
    pub var equal_type: NodeId?;
}
pub struct ImportDeclAst {
    pub var visibility: String;
    pub var path: String;
    pub var module: Vec<String>;
    pub var alias: String?;
}
pub struct ParamAst {
    pub var external_name: String?;
    pub var internal_name: String;
    pub var type_annotation: NodeId?;
    pub var default_value: NodeId?;
}
pub struct AccessorAst {
    pub var kind: String;
    pub var param_name: String?;
    pub var body: NodeId?;
}
pub struct PropertyDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var type_annotation: NodeId?;
    pub var initializer: NodeId?;
    pub var is_mutable: Bool;
    pub var accessors: Vec<NodeId>?;
}
pub struct FuncDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var params: Vec<NodeId>;
    pub var return_type: NodeId?;
    pub var constraints: Vec<NodeId>;
    pub var body: NodeId?;
    pub var is_async: Bool;
    pub var is_static: Bool;
    pub var is_unsafe: Bool;
}
pub struct ExternFuncDeclAst {
    pub var visibility: String;
    pub var abi: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var params: Vec<NodeId>;
    pub var return_type: NodeId?;
    pub var constraints: Vec<NodeId>;
    pub var is_async: Bool;
}
pub struct StructDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var constraints: Vec<NodeId>;
    pub var members: Vec<NodeId>;
}
pub struct EnumCaseDefAst {
    pub var name: String;
    pub var payload: Vec<(String?, NodeId)>;
}
pub struct EnumCaseDeclAst {
    pub var visibility: String;
    pub var cases: Vec<NodeId>;
}
pub struct EnumDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var constraints: Vec<NodeId>;
    pub var members: Vec<NodeId>;
}
pub struct ProtocolFuncReqAst {
    pub var visibility: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var params: Vec<NodeId>;
    pub var return_type: NodeId?;
    pub var is_async: Bool;
}
pub struct ProtocolPropReqAst {
    pub var visibility: String;
    pub var name: String;
    pub var type_annotation: NodeId?;
    pub var is_mutable: Bool;
    pub var has_getter: Bool;
    pub var has_setter: Bool;
}
pub struct AssociatedTypeDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var constraints: Vec<NodeId>;
}
pub struct ProtocolDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var generic_params: Vec<NodeId>;
    pub var constraints: Vec<NodeId>;
    pub var members: Vec<NodeId>;
}
pub struct ExtensionDeclAst {
    pub var visibility: String;
    pub var generic_params: Vec<NodeId>;
    pub var extended_type: NodeId?;
    pub var conformances: Vec<NodeId>;
    pub var constraints: Vec<NodeId>;
    pub var members: Vec<NodeId>;
}
// Module-level `let NAME = value;`: a compile-time constant inlined at each use.
pub struct ConstantDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var type_annotation: NodeId?;
    pub var value: NodeId?;
}
pub struct TypeAliasDeclAst {
    pub var visibility: String;
    pub var name: String;
    pub var aliased_type: NodeId?;
    pub var generic_params: Vec<NodeId>;
}

pub enum NodeForm {
    case program(ProgramAst);
    case builtin_type(BuiltinTypeAst);
    case named_type(NamedTypeAst);
    case optional_type(OptionalTypeAst);
    case array_type(ArrayTypeAst);
    case dict_type(DictTypeAst);
    case tuple_type(TupleTypeAst);
    case function_type(FunctionTypeAst);
    case any_type(AnyTypeAst);
    case pointer_type;
    case wildcard_pattern;
    case identifier_pattern(IdentifierPatternAst);
    case literal_pattern(LiteralPatternAst);
    case tuple_pattern(TuplePatternAst);
    case enum_case_pattern(EnumCasePatternAst);
    case typed_pattern(TypedPatternAst);
    case or_pattern(OrPatternAst);
    case literal(LiteralAst);
    case identifier(IdentifierAst);
    case type_reference(TypeReferenceAst);
    case binary_op(BinaryOpAst);
    case unary_op(UnaryOpAst);
    case ternary_op(TernaryOpAst);
    case argument(ArgumentAst);
    case call(CallAst);
    case try_expr(TryExprAst);
    case member_access(MemberAccessAst);
    case optional_chain(OptionalChainAst);
    case subscript(SubscriptAst);
    case tuple_expr(TupleExprAst);
    case array_literal(ArrayLiteralAst);
    case dict_literal(DictLiteralAst);
    case lambda(LambdaAst);
    case struct_literal(StructLiteralAst);
    case size_of_expr(SizeOfExprAst);
    case type_id_expr(TypeIdExprAst);
    case align_of_expr(AlignOfExprAst);
    case drop_of_expr(DropOfExprAst);
    case clone_of_expr(CloneOfExprAst);
    case cast(CastAst);
    case type_check(TypeCheckAst);
    case var_decl(VarDeclAst);
    case assignment(AssignmentAst);
    case expr_stmt(ExprStmtAst);
    case return_stmt(ReturnStmtAst);
    case break_stmt;
    case continue_stmt;
    case block(BlockAst);
    case if_stmt(IfStmtAst);
    case guard_stmt(GuardStmtAst);
    case while_stmt(WhileStmtAst);
    case for_stmt(ForStmtAst);
    case switch_case(SwitchCaseAst);
    case switch_stmt(SwitchStmtAst);
    case switch_expr(SwitchExprAst);
    case defer_stmt(DeferStmtAst);
    case generic_param(GenericParamAst);
    case constraint(ConstraintAst);
    case import_decl(ImportDeclAst);
    case param(ParamAst);
    case accessor(AccessorAst);
    case property_decl(PropertyDeclAst);
    case func_decl(FuncDeclAst);
    case extern_func_decl(ExternFuncDeclAst);
    case struct_decl(StructDeclAst);
    case enum_case_def(EnumCaseDefAst);
    case enum_case_decl(EnumCaseDeclAst);
    case enum_decl(EnumDeclAst);
    case protocol_func_req(ProtocolFuncReqAst);
    case protocol_prop_req(ProtocolPropReqAst);
    case associated_type_decl(AssociatedTypeDeclAst);
    case protocol_decl(ProtocolDeclAst);
    case extension_decl(ExtensionDeclAst);
    case type_alias_decl(TypeAliasDeclAst);
    case constant_decl(ConstantDeclAst);

    pub def kind() -> String {
        switch self {
            case .program(_): "Program";
            case .builtin_type(_): "BuiltinType";
            case .named_type(_): "NamedType";
            case .optional_type(_): "OptionalType";
            case .array_type(_): "ArrayType";
            case .dict_type(_): "DictType";
            case .tuple_type(_): "TupleType";
            case .function_type(_): "FunctionType";
            case .any_type(_): "AnyType";
            case .pointer_type: "PointerType";
            case .wildcard_pattern: "WildcardPattern";
            case .identifier_pattern(_): "IdentifierPattern";
            case .literal_pattern(_): "LiteralPattern";
            case .tuple_pattern(_): "TuplePattern";
            case .enum_case_pattern(_): "EnumCasePattern";
            case .typed_pattern(_): "TypedPattern";
            case .or_pattern(_): "OrPattern";
            case .literal(_): "Literal";
            case .identifier(_): "Identifier";
            case .type_reference(_): "TypeReference";
            case .binary_op(_): "BinaryOp";
            case .unary_op(_): "UnaryOp";
            case .ternary_op(_): "TernaryOp";
            case .argument(_): "Argument";
            case .call(_): "Call";
            case .try_expr(_): "TryExpr";
            case .member_access(_): "MemberAccess";
            case .optional_chain(_): "OptionalChain";
            case .subscript(_): "Subscript";
            case .tuple_expr(_): "TupleExpr";
            case .array_literal(_): "ArrayLiteral";
            case .dict_literal(_): "DictLiteral";
            case .lambda(_): "Lambda";
            case .struct_literal(_): "StructLiteral";
            case .size_of_expr(_): "SizeOfExpr";
            case .type_id_expr(_): "TypeIdExpr";
            case .align_of_expr(_): "AlignOfExpr";
            case .drop_of_expr(_): "DropOfExpr";
            case .clone_of_expr(_): "CloneOfExpr";
            case .cast(_): "Cast";
            case .type_check(_): "TypeCheck";
            case .var_decl(_): "VarDecl";
            case .assignment(_): "Assignment";
            case .expr_stmt(_): "ExprStmt";
            case .return_stmt(_): "ReturnStmt";
            case .break_stmt: "BreakStmt";
            case .continue_stmt: "ContinueStmt";
            case .block(_): "Block";
            case .if_stmt(_): "IfStmt";
            case .guard_stmt(_): "GuardStmt";
            case .while_stmt(_): "WhileStmt";
            case .for_stmt(_): "ForStmt";
            case .switch_case(_): "SwitchCase";
            case .switch_stmt(_): "SwitchStmt";
            case .switch_expr(_): "SwitchExpr";
            case .defer_stmt(_): "DeferStmt";
            case .generic_param(_): "GenericParam";
            case .constraint(_): "Constraint";
            case .import_decl(_): "ImportDecl";
            case .param(_): "Param";
            case .accessor(_): "Accessor";
            case .property_decl(_): "PropertyDecl";
            case .func_decl(_): "FuncDecl";
            case .extern_func_decl(_): "ExternFuncDecl";
            case .struct_decl(_): "StructDecl";
            case .enum_case_def(_): "EnumCaseDef";
            case .enum_case_decl(_): "EnumCaseDecl";
            case .enum_decl(_): "EnumDecl";
            case .protocol_func_req(_): "ProtocolFuncReq";
            case .protocol_prop_req(_): "ProtocolPropReq";
            case .associated_type_decl(_): "AssociatedTypeDecl";
            case .protocol_decl(_): "ProtocolDecl";
            case .extension_decl(_): "ExtensionDecl";
            case .type_alias_decl(_): "TypeAliasDecl";
            case .constant_decl(_): "ConstantDecl";
        }
    }
    pub def category() -> NodeCategory {
        switch self {
            case .program(_): NodeCategory.program();
            case .builtin_type(_): NodeCategory.type_syntax();
            case .named_type(_): NodeCategory.type_syntax();
            case .optional_type(_): NodeCategory.type_syntax();
            case .array_type(_): NodeCategory.type_syntax();
            case .dict_type(_): NodeCategory.type_syntax();
            case .tuple_type(_): NodeCategory.type_syntax();
            case .function_type(_): NodeCategory.type_syntax();
            case .any_type(_): NodeCategory.type_syntax();
            case .pointer_type: NodeCategory.type_syntax();
            case .wildcard_pattern: NodeCategory.pattern();
            case .identifier_pattern(_): NodeCategory.pattern();
            case .literal_pattern(_): NodeCategory.pattern();
            case .tuple_pattern(_): NodeCategory.pattern();
            case .enum_case_pattern(_): NodeCategory.pattern();
            case .typed_pattern(_): NodeCategory.pattern();
            case .or_pattern(_): NodeCategory.pattern();
            case .literal(_): NodeCategory.expression();
            case .identifier(_): NodeCategory.expression();
            case .type_reference(_): NodeCategory.expression();
            case .binary_op(_): NodeCategory.expression();
            case .unary_op(_): NodeCategory.expression();
            case .ternary_op(_): NodeCategory.expression();
            case .argument(_): NodeCategory.auxiliary();
            case .call(_): NodeCategory.expression();
            case .try_expr(_): NodeCategory.expression();
            case .member_access(_): NodeCategory.expression();
            case .optional_chain(_): NodeCategory.expression();
            case .subscript(_): NodeCategory.expression();
            case .tuple_expr(_): NodeCategory.expression();
            case .array_literal(_): NodeCategory.expression();
            case .dict_literal(_): NodeCategory.expression();
            case .lambda(_): NodeCategory.expression();
            case .struct_literal(_): NodeCategory.expression();
            case .size_of_expr(_): NodeCategory.expression();
            case .type_id_expr(_): NodeCategory.expression();
            case .align_of_expr(_): NodeCategory.expression();
            case .drop_of_expr(_): NodeCategory.expression();
            case .clone_of_expr(_): NodeCategory.expression();
            case .cast(_): NodeCategory.expression();
            case .type_check(_): NodeCategory.expression();
            case .var_decl(_): NodeCategory.statement();
            case .assignment(_): NodeCategory.statement();
            case .expr_stmt(_): NodeCategory.statement();
            case .return_stmt(_): NodeCategory.statement();
            case .break_stmt: NodeCategory.statement();
            case .continue_stmt: NodeCategory.statement();
            case .block(_): NodeCategory.statement();
            case .if_stmt(_): NodeCategory.statement();
            case .guard_stmt(_): NodeCategory.statement();
            case .while_stmt(_): NodeCategory.statement();
            case .for_stmt(_): NodeCategory.statement();
            case .switch_case(_): NodeCategory.auxiliary();
            case .switch_stmt(_): NodeCategory.statement();
            case .switch_expr(_): NodeCategory.expression();
            case .defer_stmt(_): NodeCategory.statement();
            case .generic_param(_): NodeCategory.auxiliary();
            case .constraint(_): NodeCategory.auxiliary();
            case .import_decl(_): NodeCategory.declaration();
            case .param(_): NodeCategory.auxiliary();
            case .accessor(_): NodeCategory.auxiliary();
            case .property_decl(_): NodeCategory.auxiliary();
            case .func_decl(_): NodeCategory.declaration();
            case .extern_func_decl(_): NodeCategory.declaration();
            case .struct_decl(_): NodeCategory.declaration();
            case .enum_case_def(_): NodeCategory.auxiliary();
            case .enum_case_decl(_): NodeCategory.auxiliary();
            case .enum_decl(_): NodeCategory.declaration();
            case .protocol_func_req(_): NodeCategory.auxiliary();
            case .protocol_prop_req(_): NodeCategory.auxiliary();
            case .associated_type_decl(_): NodeCategory.auxiliary();
            case .protocol_decl(_): NodeCategory.declaration();
            case .extension_decl(_): NodeCategory.declaration();
            case .type_alias_decl(_): NodeCategory.declaration();
            case .constant_decl(_): NodeCategory.declaration();
        }
    }
    pub def children() -> Vec<NodeId> {
        let result = Vec<NodeId>.new();
        switch self {
            case .program(let data):
                for child in data.items { result.push(child); }
            case .named_type(let data):
                for child in data.generic_args { result.push(child); }
            case .optional_type(let data):
                if let child = data.inner { result.push(child); }
            case .array_type(let data):
                if let child = data.element { result.push(child); }
            case .dict_type(let data):
                if let child = data.key { result.push(child); }
                if let child = data.value { result.push(child); }
            case .tuple_type(let data):
                for pair in data.elements { result.push(pair.1); }
            case .function_type(let data):
                for child in data.params { result.push(child); }
                if let child = data.return_type { result.push(child); }
            case .any_type(let data):
                if let child = data.protocol { result.push(child); }
            case .literal_pattern(let data):
                if let child = data.value { result.push(child); }
            case .tuple_pattern(let data):
                for pair in data.elements { result.push(pair.1); }
            case .enum_case_pattern(let data):
                for child in data.payload { result.push(child); }
            case .typed_pattern(let data):
                if let child = data.pattern { result.push(child); }
                if let child = data.type_annotation { result.push(child); }
            case .or_pattern(let data):
                for child in data.patterns { result.push(child); }
            case .type_reference(let data):
                if let child = data.type_name { result.push(child); }
            case .binary_op(let data):
                if let child = data.left { result.push(child); }
                if let child = data.right { result.push(child); }
            case .unary_op(let data):
                if let child = data.operand { result.push(child); }
            case .ternary_op(let data):
                if let child = data.condition { result.push(child); }
                if let child = data.then_expr { result.push(child); }
                if let child = data.else_expr { result.push(child); }
            case .argument(let data):
                if let child = data.value { result.push(child); }
            case .call(let data):
                if let child = data.callee { result.push(child); }
                for child in data.arguments { result.push(child); }
            case .try_expr(let data):
                if let child = data.value { result.push(child); }
            case .member_access(let data):
                if let child = data.object { result.push(child); }
            case .optional_chain(let data):
                if let child = data.object { result.push(child); }
                if let suffix = data.suffix { switch suffix {
                    case .call(let args): for child in args { result.push(child); }
                    case .index(let indices): for child in indices { result.push(child); }
                } }
            case .subscript(let data):
                if let child = data.object { result.push(child); }
                for child in data.indices { result.push(child); }
            case .tuple_expr(let data):
                for pair in data.elements { result.push(pair.1); }
            case .array_literal(let data):
                for child in data.elements { result.push(child); }
            case .dict_literal(let data):
                for pair in data.entries { result.push(pair.0); result.push(pair.1); }
            case .lambda(let data):
                for pair in data.params { result.push(pair.0); if let child = pair.1 { result.push(child); } }
                if let child = data.return_type { result.push(child); }
                for child in data.body { result.push(child); }
            case .struct_literal(let data):
                if let child = data.type_name { result.push(child); }
                for child in data.arguments { result.push(child); }
            case .size_of_expr(let data):
                if let child = data.type_arg { result.push(child); }
            case .type_id_expr(let data):
                if let child = data.type_arg { result.push(child); }
            case .align_of_expr(let data):
                if let child = data.type_arg { result.push(child); }
            case .drop_of_expr(let data):
                if let child = data.type_arg { result.push(child); }
            case .clone_of_expr(let data):
                if let child = data.type_arg { result.push(child); }
            case .cast(let data):
                if let child = data.expr { result.push(child); }
                if let child = data.target_type { result.push(child); }
            case .type_check(let data):
                if let child = data.expr { result.push(child); }
                if let child = data.checked_type { result.push(child); }
            case .var_decl(let data):
                if let child = data.pattern { result.push(child); }
                if let child = data.type_annotation { result.push(child); }
                if let child = data.initializer { result.push(child); }
            case .assignment(let data):
                if let child = data.target { result.push(child); }
                if let child = data.value { result.push(child); }
            case .expr_stmt(let data):
                if let child = data.expr { result.push(child); }
            case .return_stmt(let data):
                if let child = data.value { result.push(child); }
            case .block(let data):
                for child in data.statements { result.push(child); }
            case .if_stmt(let data):
                if let condition = data.condition { switch condition {
                    case .expression(let child): result.push(child);
                    case .binding(let pattern, let value): result.push(pattern); result.push(value);
                } }
                if let child = data.then_block { result.push(child); }
                if let child = data.else_block { result.push(child); }
            case .guard_stmt(let data):
                if let condition = data.condition { switch condition {
                    case .expression(let child): result.push(child);
                    case .binding(let pattern, let value): result.push(pattern); result.push(value);
                } }
                if let child = data.else_block { result.push(child); }
            case .while_stmt(let data):
                if let child = data.condition { result.push(child); }
                if let child = data.body { result.push(child); }
            case .for_stmt(let data):
                if let child = data.pattern { result.push(child); }
                if let child = data.iterable { result.push(child); }
                if let child = data.body { result.push(child); }
            case .switch_case(let data):
                for pair in data.patterns { result.push(pair.0); if let child = pair.1 { result.push(child); } }
                for child in data.body { result.push(child); }
            case .switch_stmt(let data):
                if let child = data.value { result.push(child); }
                for child in data.cases { result.push(child); }
            case .switch_expr(let data):
                if let child = data.value { result.push(child); }
                for child in data.cases { result.push(child); }
            case .defer_stmt(let data):
                if let child = data.body { result.push(child); }
            case .generic_param(let data):
                if let values = data.bounds { for child in values { result.push(child); } }
            case .constraint(let data):
                if let subject = data.subject { switch subject {
                    case .type_ref(let child): result.push(child);
                    case .name(_): {}
                } }
                for child in data.bounds { result.push(child); }
                if let child = data.equal_type { result.push(child); }
            case .param(let data):
                if let child = data.type_annotation { result.push(child); }
                if let child = data.default_value { result.push(child); }
            case .accessor(let data):
                if let child = data.body { result.push(child); }
            case .property_decl(let data):
                if let child = data.type_annotation { result.push(child); }
                if let child = data.initializer { result.push(child); }
                if let values = data.accessors { for child in values { result.push(child); } }
            case .func_decl(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.params { result.push(child); }
                if let child = data.return_type { result.push(child); }
                for child in data.constraints { result.push(child); }
                if let child = data.body { result.push(child); }
            case .extern_func_decl(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.params { result.push(child); }
                if let child = data.return_type { result.push(child); }
                for child in data.constraints { result.push(child); }
            case .struct_decl(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.constraints { result.push(child); }
                for child in data.members { result.push(child); }
            case .enum_case_def(let data):
                for pair in data.payload { result.push(pair.1); }
            case .enum_case_decl(let data):
                for child in data.cases { result.push(child); }
            case .enum_decl(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.constraints { result.push(child); }
                for child in data.members { result.push(child); }
            case .protocol_func_req(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.params { result.push(child); }
                if let child = data.return_type { result.push(child); }
            case .protocol_prop_req(let data):
                if let child = data.type_annotation { result.push(child); }
            case .associated_type_decl(let data):
                for child in data.constraints { result.push(child); }
            case .protocol_decl(let data):
                for child in data.generic_params { result.push(child); }
                for child in data.constraints { result.push(child); }
                for child in data.members { result.push(child); }
            case .extension_decl(let data):
                for child in data.generic_params { result.push(child); }
                if let child = data.extended_type { result.push(child); }
                for child in data.conformances { result.push(child); }
                for child in data.constraints { result.push(child); }
                for child in data.members { result.push(child); }
            case .type_alias_decl(let data):
                if let child = data.aliased_type { result.push(child); }
                for child in data.generic_params { result.push(child); }
            case .constant_decl(let data):
                if let child = data.type_annotation { result.push(child); }
                if let child = data.value { result.push(child); }
            default: {}
        }
        result
    }
}
