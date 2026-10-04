// Checked-in Rolang definitions. Keep node fields, visitors and dumps in sync.
pub import "ids.rl"
// Decimal text preserves source integers until LLVM emission.
pub enum HirValue { case integer(String); case floating(f64); case boolean(Bool); case text(String); case none; case type_id(TypeId); }

pub struct HirProgramData {
    pub var items: Vec<HirId>;
}
pub struct HirFunctionData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var params: Vec<HirId>;
    pub var return_type: TypeId;
    pub var body: HirId?;
    pub var is_async: Bool;
    pub var is_method: Bool;
    pub var is_static: Bool;
}
pub struct HirExternFuncData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var abi: String;
    pub var params: Vec<HirId>;
    pub var return_type: TypeId;
}
pub struct HirParamData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var type_id: TypeId;
    pub var external_name: String?;
    pub var has_default: Bool;
}
pub struct HirStructData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var fields: Vec<HirId>;
    pub var methods: Vec<HirId>;
}
pub struct HirFieldData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var type_id: TypeId;
    pub var is_mutable: Bool;
    pub var default_value: HirId?;
}
pub struct HirEnumData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var cases: Vec<HirId>;
    pub var methods: Vec<HirId>;
}
pub struct HirEnumCaseData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var payload: Vec<(String?, TypeId)>;
}
pub struct HirProtocolData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var func_requirements: Vec<HirId>;
    pub var prop_requirements: Vec<HirId>;
}
pub struct HirFuncRequirementData {
    pub var name: String;
    pub var params: Vec<(String?, TypeId)>;
    pub var return_type: TypeId;
    pub var is_async: Bool;
}
pub struct HirPropRequirementData {
    pub var name: String;
    pub var type_id: TypeId;
    pub var has_getter: Bool;
    pub var has_setter: Bool;
}
pub struct HirExtensionData {
    pub var extended_type: TypeId;
    pub var methods: Vec<HirId>;
}
pub struct HirBlockData {
    pub var statements: Vec<HirId>;
}
pub struct HirVarDeclData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var type_id: TypeId;
    pub var initializer: HirId?;
    pub var is_mutable: Bool;
}
pub struct HirAssignData {
    pub var target: HirId;
    pub var value: HirId;
    pub var compound_op: String?;
}
pub struct HirExprStmtData {
    pub var expr: HirId;
}
pub struct HirReturnData {
    pub var value: HirId?;
}
pub struct HirIfData {
    pub var condition: HirId;
    pub var then_block: HirId;
    pub var else_block: HirId?;
}
pub struct HirIfLetData {
    pub var pattern: HirId;
    pub var scrutinee: HirId;
    pub var then_block: HirId;
    pub var else_block: HirId?;
}
pub struct HirGuardData {
    pub var condition: HirId;
    pub var else_block: HirId;
}
pub struct HirWhileData {
    pub var condition: HirId;
    pub var body: HirId;
    pub var label: String? = nil;
}
pub struct HirForData {
    pub var pattern: HirId;
    pub var iterable: HirId;
    pub var body: HirId;
    pub var label: String? = nil;
}
pub struct HirSwitchCaseData {
    pub var patterns: Vec<(HirId, HirId?)>;
    pub var body: HirId;
    pub var is_default: Bool;
}
pub struct HirSwitchData {
    pub var scrutinee: HirId;
    pub var scrutinee_type: TypeId;
    pub var cases: Vec<HirId>;
}
pub struct HirDeferData {
    pub var body: HirId;
}
pub struct HirLiteralData {
    pub var type_id: TypeId;
    pub var value: HirValue;
    pub var kind: String;
}
pub struct HirVarData {
    pub var type_id: TypeId;
    pub var name: String;
    pub var symbol_id: SymbolId;
}
pub struct HirBinaryOpData {
    pub var type_id: TypeId;
    pub var left: HirId;
    pub var op: String;
    pub var right: HirId;
}
pub struct HirUnaryOpData {
    pub var type_id: TypeId;
    pub var op: String;
    pub var operand: HirId;
}
pub struct HirTernaryData {
    pub var type_id: TypeId;
    pub var condition: HirId;
    pub var then_expr: HirId;
    pub var else_expr: HirId;
}
pub struct HirCallData {
    pub var type_id: TypeId;
    pub var callee: HirId;
    pub var arguments: Vec<(String?, HirId)>;
    pub var callee_symbol: SymbolId?;
}
pub struct HirMethodCallData {
    pub var type_id: TypeId;
    pub var receiver: HirId;
    pub var method_name: String;
    pub var arguments: Vec<(String?, HirId)>;
    pub var method_symbol: SymbolId?;
    pub var is_static: Bool;
}
pub struct HirFieldAccessData {
    pub var type_id: TypeId;
    pub var object: HirId;
    pub var field_name: String;
    pub var field_symbol: SymbolId?;
}
pub struct HirSubscriptData {
    pub var type_id: TypeId;
    pub var object: HirId;
    pub var indices: Vec<HirId>;
}
pub struct HirTupleData {
    pub var type_id: TypeId;
    pub var elements: Vec<(String?, HirId)>;
}
pub struct HirArrayData {
    pub var type_id: TypeId;
    pub var elements: Vec<HirId>;
    pub var element_type: TypeId;
}
pub struct HirDictData {
    pub var type_id: TypeId;
    pub var entries: Vec<(HirId, HirId)>;
    pub var key_type: TypeId;
    pub var value_type: TypeId;
}
pub struct HirLambdaData {
    pub var type_id: TypeId;
    pub var params: Vec<HirId>;
    pub var body: HirId;
    pub var captures: Vec<SymbolId>;
}
pub struct HirCloneData {
    pub var type_id: TypeId;
    pub var value: HirId;
}
pub struct HirStructInitData {
    pub var type_id: TypeId;
    pub var struct_type: TypeId;
    pub var struct_symbol: SymbolId;
    pub var arguments: Vec<(String?, HirId)>;
}
pub struct HirEnumConstructData {
    pub var type_id: TypeId;
    pub var enum_type: TypeId;
    pub var case_name: String;
    pub var case_symbol: SymbolId?;
    pub var payload: Vec<(String?, HirId)>;
}
pub struct HirSwitchExprData {
    pub var type_id: TypeId;
    pub var switch: HirId;
    pub var result_symbol: SymbolId;
}
pub struct HirTryExprData {
    pub var type_id: TypeId;
    pub var expr: HirId;
    pub var result_type: TypeId;
    pub var error_type: TypeId?;
}
pub struct HirCastData {
    pub var type_id: TypeId;
    pub var expr: HirId;
    pub var target_type: TypeId;
    pub var kind: String;
}
pub struct HirTypeCheckData {
    pub var type_id: TypeId;
    pub var expr: HirId;
    pub var checked_type: TypeId;
}
pub struct HirOptionalSomeData {
    pub var type_id: TypeId;
    pub var value: HirId;
    pub var inner_type: TypeId;
}
pub struct HirOptionalNoneData {
    pub var type_id: TypeId;
    pub var inner_type: TypeId;
}
pub struct HirOptionalMatchData {
    pub var type_id: TypeId;
    pub var scrutinee: HirId;
    pub var inner_type: TypeId;
    pub var some_binding: SymbolId;
    pub var some_expr: HirId;
    pub var none_expr: HirId;
}
pub struct HirBindingPatternData {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var type_id: TypeId;
    pub var is_mutable: Bool;
}
pub struct HirLiteralPatternData {
    pub var value: HirValue;
    pub var type_id: TypeId;
    // The other end of a range pattern, `value...upper` or `value..<upper`.
    pub var upper: HirValue? = nil;
    pub var inclusive: Bool = false;
}
pub struct HirTuplePatternData {
    pub var elements: Vec<(String?, HirId)>;
    pub var type_id: TypeId;
}
pub struct HirEnumCasePatternData {
    pub var case_name: String;
    pub var case_symbol: SymbolId?;
    pub var payload: Vec<HirId>;
    pub var enum_type: TypeId;
}
pub struct HirOrPatternData {
    pub var patterns: Vec<HirId>;
    pub var type_id: TypeId;
}

pub enum HirForm {
    case program(HirProgramData);
    case function(HirFunctionData);
    case extern_func(HirExternFuncData);
    case param(HirParamData);
    case struct_type(HirStructData);
    case field(HirFieldData);
    case enum_type(HirEnumData);
    case enum_case(HirEnumCaseData);
    case protocol(HirProtocolData);
    case func_requirement(HirFuncRequirementData);
    case prop_requirement(HirPropRequirementData);
    case extension(HirExtensionData);
    case block(HirBlockData);
    case var_decl(HirVarDeclData);
    case assign(HirAssignData);
    case expr_stmt(HirExprStmtData);
    case return_stmt(HirReturnData);
    // The label of the loop to leave or continue; nil for the innermost loop.
    case break_stmt(String?);
    case continue_stmt(String?);
    case if_stmt(HirIfData);
    case if_let(HirIfLetData);
    case guard_stmt(HirGuardData);
    case while_stmt(HirWhileData);
    case for_stmt(HirForData);
    case switch_case(HirSwitchCaseData);
    case switch_stmt(HirSwitchData);
    case defer_stmt(HirDeferData);
    case literal(HirLiteralData);
    case var_ref(HirVarData);
    case binary_op(HirBinaryOpData);
    case unary_op(HirUnaryOpData);
    case ternary(HirTernaryData);
    case call(HirCallData);
    case method_call(HirMethodCallData);
    case field_access(HirFieldAccessData);
    case subscript(HirSubscriptData);
    case tuple(HirTupleData);
    case array(HirArrayData);
    case dict(HirDictData);
    case lambda(HirLambdaData);
    case clone(HirCloneData);
    case struct_init(HirStructInitData);
    case enum_construct(HirEnumConstructData);
    case switch_expr(HirSwitchExprData);
    case try_expr(HirTryExprData);
    case cast(HirCastData);
    case type_check(HirTypeCheckData);
    case optional_some(HirOptionalSomeData);
    case optional_none(HirOptionalNoneData);
    case optional_match(HirOptionalMatchData);
    case wildcard_pattern;
    case binding_pattern(HirBindingPatternData);
    case literal_pattern(HirLiteralPatternData);
    case tuple_pattern(HirTuplePatternData);
    case enum_case_pattern(HirEnumCasePatternData);
    case or_pattern(HirOrPatternData);

    pub def kind() -> String {
        switch self {
            case .program(_): "HirProgram";
            case .function(_): "HirFunction";
            case .extern_func(_): "HirExternFunc";
            case .param(_): "HirParam";
            case .struct_type(_): "HirStruct";
            case .field(_): "HirField";
            case .enum_type(_): "HirEnum";
            case .enum_case(_): "HirEnumCase";
            case .protocol(_): "HirProtocol";
            case .func_requirement(_): "HirFuncRequirement";
            case .prop_requirement(_): "HirPropRequirement";
            case .extension(_): "HirExtension";
            case .block(_): "HirBlock";
            case .var_decl(_): "HirVarDecl";
            case .assign(_): "HirAssign";
            case .expr_stmt(_): "HirExprStmt";
            case .return_stmt(_): "HirReturn";
            case .break_stmt: "HirBreak";
            case .continue_stmt: "HirContinue";
            case .if_stmt(_): "HirIf";
            case .if_let(_): "HirIfLet";
            case .guard_stmt(_): "HirGuard";
            case .while_stmt(_): "HirWhile";
            case .for_stmt(_): "HirFor";
            case .switch_case(_): "HirSwitchCase";
            case .switch_stmt(_): "HirSwitch";
            case .defer_stmt(_): "HirDefer";
            case .literal(_): "HirLiteral";
            case .var_ref(_): "HirVar";
            case .binary_op(_): "HirBinaryOp";
            case .unary_op(_): "HirUnaryOp";
            case .ternary(_): "HirTernary";
            case .call(_): "HirCall";
            case .method_call(_): "HirMethodCall";
            case .field_access(_): "HirFieldAccess";
            case .subscript(_): "HirSubscript";
            case .tuple(_): "HirTuple";
            case .array(_): "HirArray";
            case .dict(_): "HirDict";
            case .lambda(_): "HirLambda";
            case .clone(_): "HirClone";
            case .struct_init(_): "HirStructInit";
            case .enum_construct(_): "HirEnumConstruct";
            case .switch_expr(_): "HirSwitchExpr";
            case .try_expr(_): "HirTryExpr";
            case .cast(_): "HirCast";
            case .type_check(_): "HirTypeCheck";
            case .optional_some(_): "HirOptionalSome";
            case .optional_none(_): "HirOptionalNone";
            case .optional_match(_): "HirOptionalMatch";
            case .wildcard_pattern: "HirWildcardPattern";
            case .binding_pattern(_): "HirBindingPattern";
            case .literal_pattern(_): "HirLiteralPattern";
            case .tuple_pattern(_): "HirTuplePattern";
            case .enum_case_pattern(_): "HirEnumCasePattern";
            case .or_pattern(_): "HirOrPattern";
        }
    }
    pub def type_id() -> TypeId? {
        switch self {
            case .param(let data): return data.type_id;
            case .field(let data): return data.type_id;
            case .prop_requirement(let data): return data.type_id;
            case .var_decl(let data): return data.type_id;
            case .literal(let data): return data.type_id;
            case .var_ref(let data): return data.type_id;
            case .binary_op(let data): return data.type_id;
            case .unary_op(let data): return data.type_id;
            case .ternary(let data): return data.type_id;
            case .call(let data): return data.type_id;
            case .method_call(let data): return data.type_id;
            case .field_access(let data): return data.type_id;
            case .subscript(let data): return data.type_id;
            case .tuple(let data): return data.type_id;
            case .array(let data): return data.type_id;
            case .dict(let data): return data.type_id;
            case .lambda(let data): return data.type_id;
            case .clone(let data): return data.type_id;
            case .struct_init(let data): return data.type_id;
            case .enum_construct(let data): return data.type_id;
            case .switch_expr(let data): return data.type_id;
            case .try_expr(let data): return data.type_id;
            case .cast(let data): return data.type_id;
            case .type_check(let data): return data.type_id;
            case .optional_some(let data): return data.type_id;
            case .optional_none(let data): return data.type_id;
            case .optional_match(let data): return data.type_id;
            case .binding_pattern(let data): return data.type_id;
            case .literal_pattern(let data): return data.type_id;
            case .tuple_pattern(let data): return data.type_id;
            case .or_pattern(let data): return data.type_id;
            default: return nil;
        }
    }
    pub def children() -> Vec<HirId> {
        let result = Vec<HirId>.new();
        switch self {
            case .program(let data):
                for child in data.items { result.push(child); }
            case .function(let data):
                for child in data.params { result.push(child); }
                if let child = data.body { result.push(child); }
            case .extern_func(let data):
                for child in data.params { result.push(child); }
            case .struct_type(let data):
                for child in data.fields { result.push(child); }
                for child in data.methods { result.push(child); }
            case .field(let data):
                if let child = data.default_value { result.push(child); }
            case .enum_type(let data):
                for child in data.cases { result.push(child); }
                for child in data.methods { result.push(child); }
            case .protocol(let data):
                for child in data.func_requirements { result.push(child); }
                for child in data.prop_requirements { result.push(child); }
            case .extension(let data):
                for child in data.methods { result.push(child); }
            case .block(let data):
                for child in data.statements { result.push(child); }
            case .var_decl(let data):
                if let child = data.initializer { result.push(child); }
            case .assign(let data):
                result.push(data.target);
                result.push(data.value);
            case .expr_stmt(let data):
                result.push(data.expr);
            case .return_stmt(let data):
                if let child = data.value { result.push(child); }
            case .if_stmt(let data):
                result.push(data.condition);
                result.push(data.then_block);
                if let child = data.else_block { result.push(child); }
            case .if_let(let data):
                result.push(data.pattern);
                result.push(data.scrutinee);
                result.push(data.then_block);
                if let child = data.else_block { result.push(child); }
            case .guard_stmt(let data):
                result.push(data.condition);
                result.push(data.else_block);
            case .while_stmt(let data):
                result.push(data.condition);
                result.push(data.body);
            case .for_stmt(let data):
                result.push(data.pattern);
                result.push(data.iterable);
                result.push(data.body);
            case .switch_case(let data):
                for pair in data.patterns { result.push(pair.0); if let child = pair.1 { result.push(child); } }
                result.push(data.body);
            case .switch_stmt(let data):
                result.push(data.scrutinee);
                for child in data.cases { result.push(child); }
            case .defer_stmt(let data):
                result.push(data.body);
            case .binary_op(let data):
                result.push(data.left);
                result.push(data.right);
            case .unary_op(let data):
                result.push(data.operand);
            case .ternary(let data):
                result.push(data.condition);
                result.push(data.then_expr);
                result.push(data.else_expr);
            case .call(let data):
                result.push(data.callee);
                for pair in data.arguments { result.push(pair.1); }
            case .method_call(let data):
                result.push(data.receiver);
                for pair in data.arguments { result.push(pair.1); }
            case .field_access(let data):
                result.push(data.object);
            case .subscript(let data):
                result.push(data.object);
                for child in data.indices { result.push(child); }
            case .tuple(let data):
                for pair in data.elements { result.push(pair.1); }
            case .array(let data):
                for child in data.elements { result.push(child); }
            case .dict(let data):
                for pair in data.entries { result.push(pair.0); result.push(pair.1); }
            case .lambda(let data):
                for child in data.params { result.push(child); }
                result.push(data.body);
            case .clone(let data):
                result.push(data.value);
            case .struct_init(let data):
                for pair in data.arguments { result.push(pair.1); }
            case .enum_construct(let data):
                for pair in data.payload { result.push(pair.1); }
            case .switch_expr(let data):
                result.push(data.switch);
            case .try_expr(let data):
                result.push(data.expr);
            case .cast(let data):
                result.push(data.expr);
            case .type_check(let data):
                result.push(data.expr);
            case .optional_some(let data):
                result.push(data.value);
            case .optional_match(let data):
                result.push(data.scrutinee);
                result.push(data.some_expr);
                result.push(data.none_expr);
            case .tuple_pattern(let data):
                for pair in data.elements { result.push(pair.1); }
            case .enum_case_pattern(let data):
                for child in data.payload { result.push(child); }
            case .or_pattern(let data):
                for child in data.patterns { result.push(child); }
            default: {}
        }
        result
    }
    pub def remap(node: (HirId)->HirId, type: (TypeId)->TypeId) -> HirForm {
        switch self {
            case .program(let data):
                let new_items = Vec<HirId>.new();
                for x in data.items { new_items.push(node(x)); }
                return HirForm.program(HirProgramData { items: new_items });
            case .function(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_params = Vec<HirId>.new();
                for x in data.params { new_params.push(node(x)); }
                let new_return_type = type(data.return_type);
                var new_body: HirId? = nil; if let x = data.body { new_body = node(x); }
                let new_is_async = data.is_async;
                let new_is_method = data.is_method;
                let new_is_static = data.is_static;
                return HirForm.function(HirFunctionData { name: new_name, symbol_id: new_symbol_id, params: new_params, return_type: new_return_type, body: new_body, is_async: new_is_async, is_method: new_is_method, is_static: new_is_static });
            case .extern_func(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_abi = data.abi;
                let new_params = Vec<HirId>.new();
                for x in data.params { new_params.push(node(x)); }
                let new_return_type = type(data.return_type);
                return HirForm.extern_func(HirExternFuncData { name: new_name, symbol_id: new_symbol_id, abi: new_abi, params: new_params, return_type: new_return_type });
            case .param(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_type_id = type(data.type_id);
                let new_external_name = data.external_name;
                let new_has_default = data.has_default;
                return HirForm.param(HirParamData { name: new_name, symbol_id: new_symbol_id, type_id: new_type_id, external_name: new_external_name, has_default: new_has_default });
            case .struct_type(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_fields = Vec<HirId>.new();
                for x in data.fields { new_fields.push(node(x)); }
                let new_methods = Vec<HirId>.new();
                for x in data.methods { new_methods.push(node(x)); }
                return HirForm.struct_type(HirStructData { name: new_name, symbol_id: new_symbol_id, fields: new_fields, methods: new_methods });
            case .field(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_type_id = type(data.type_id);
                let new_is_mutable = data.is_mutable;
                var new_default_value: HirId? = nil; if let x = data.default_value { new_default_value = node(x); }
                return HirForm.field(HirFieldData { name: new_name, symbol_id: new_symbol_id, type_id: new_type_id, is_mutable: new_is_mutable, default_value: new_default_value });
            case .enum_type(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_cases = Vec<HirId>.new();
                for x in data.cases { new_cases.push(node(x)); }
                let new_methods = Vec<HirId>.new();
                for x in data.methods { new_methods.push(node(x)); }
                return HirForm.enum_type(HirEnumData { name: new_name, symbol_id: new_symbol_id, cases: new_cases, methods: new_methods });
            case .enum_case(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_payload = Vec<(String?, TypeId)>.new();
                for x in data.payload { new_payload.push((x.0, type(x.1))); }
                return HirForm.enum_case(HirEnumCaseData { name: new_name, symbol_id: new_symbol_id, payload: new_payload });
            case .protocol(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_func_requirements = Vec<HirId>.new();
                for x in data.func_requirements { new_func_requirements.push(node(x)); }
                let new_prop_requirements = Vec<HirId>.new();
                for x in data.prop_requirements { new_prop_requirements.push(node(x)); }
                return HirForm.protocol(HirProtocolData { name: new_name, symbol_id: new_symbol_id, func_requirements: new_func_requirements, prop_requirements: new_prop_requirements });
            case .func_requirement(let data):
                let new_name = data.name;
                let new_params = Vec<(String?, TypeId)>.new();
                for x in data.params { new_params.push((x.0, type(x.1))); }
                let new_return_type = type(data.return_type);
                let new_is_async = data.is_async;
                return HirForm.func_requirement(HirFuncRequirementData { name: new_name, params: new_params, return_type: new_return_type, is_async: new_is_async });
            case .prop_requirement(let data):
                let new_name = data.name;
                let new_type_id = type(data.type_id);
                let new_has_getter = data.has_getter;
                let new_has_setter = data.has_setter;
                return HirForm.prop_requirement(HirPropRequirementData { name: new_name, type_id: new_type_id, has_getter: new_has_getter, has_setter: new_has_setter });
            case .extension(let data):
                let new_extended_type = type(data.extended_type);
                let new_methods = Vec<HirId>.new();
                for x in data.methods { new_methods.push(node(x)); }
                return HirForm.extension(HirExtensionData { extended_type: new_extended_type, methods: new_methods });
            case .block(let data):
                let new_statements = Vec<HirId>.new();
                for x in data.statements { new_statements.push(node(x)); }
                return HirForm.block(HirBlockData { statements: new_statements });
            case .var_decl(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_type_id = type(data.type_id);
                var new_initializer: HirId? = nil; if let x = data.initializer { new_initializer = node(x); }
                let new_is_mutable = data.is_mutable;
                return HirForm.var_decl(HirVarDeclData { name: new_name, symbol_id: new_symbol_id, type_id: new_type_id, initializer: new_initializer, is_mutable: new_is_mutable });
            case .assign(let data):
                let new_target = node(data.target);
                let new_value = node(data.value);
                let new_compound_op = data.compound_op;
                return HirForm.assign(HirAssignData { target: new_target, value: new_value, compound_op: new_compound_op });
            case .expr_stmt(let data):
                let new_expr = node(data.expr);
                return HirForm.expr_stmt(HirExprStmtData { expr: new_expr });
            case .return_stmt(let data):
                var new_value: HirId? = nil; if let x = data.value { new_value = node(x); }
                return HirForm.return_stmt(HirReturnData { value: new_value });
            case .break_stmt(let label): return HirForm.break_stmt(label);
            case .continue_stmt(let label): return HirForm.continue_stmt(label);
            case .if_stmt(let data):
                let new_condition = node(data.condition);
                let new_then_block = node(data.then_block);
                var new_else_block: HirId? = nil; if let x = data.else_block { new_else_block = node(x); }
                return HirForm.if_stmt(HirIfData { condition: new_condition, then_block: new_then_block, else_block: new_else_block });
            case .if_let(let data):
                let new_pattern = node(data.pattern);
                let new_scrutinee = node(data.scrutinee);
                let new_then_block = node(data.then_block);
                var new_else_block: HirId? = nil; if let x = data.else_block { new_else_block = node(x); }
                return HirForm.if_let(HirIfLetData { pattern: new_pattern, scrutinee: new_scrutinee, then_block: new_then_block, else_block: new_else_block });
            case .guard_stmt(let data):
                let new_condition = node(data.condition);
                let new_else_block = node(data.else_block);
                return HirForm.guard_stmt(HirGuardData { condition: new_condition, else_block: new_else_block });
            case .while_stmt(let data):
                let new_condition = node(data.condition);
                let new_body = node(data.body);
                return HirForm.while_stmt(HirWhileData { condition: new_condition, body: new_body, label: data.label });
            case .for_stmt(let data):
                let new_pattern = node(data.pattern);
                let new_iterable = node(data.iterable);
                let new_body = node(data.body);
                return HirForm.for_stmt(HirForData { pattern: new_pattern, iterable: new_iterable, body: new_body, label: data.label });
            case .switch_case(let data):
                let new_patterns = Vec<(HirId, HirId?)>.new();
                for x in data.patterns { let first = node(x.0); var second: HirId? = nil; if let y = x.1 { second = node(y); } new_patterns.push((first, second)); }
                let new_body = node(data.body);
                let new_is_default = data.is_default;
                return HirForm.switch_case(HirSwitchCaseData { patterns: new_patterns, body: new_body, is_default: new_is_default });
            case .switch_stmt(let data):
                let new_scrutinee = node(data.scrutinee);
                let new_scrutinee_type = type(data.scrutinee_type);
                let new_cases = Vec<HirId>.new();
                for x in data.cases { new_cases.push(node(x)); }
                return HirForm.switch_stmt(HirSwitchData { scrutinee: new_scrutinee, scrutinee_type: new_scrutinee_type, cases: new_cases });
            case .defer_stmt(let data):
                let new_body = node(data.body);
                return HirForm.defer_stmt(HirDeferData { body: new_body });
            case .literal(let data):
                let new_type_id = type(data.type_id);
                let new_value = data.value;
                let new_kind = data.kind;
                return HirForm.literal(HirLiteralData { type_id: new_type_id, value: new_value, kind: new_kind });
            case .var_ref(let data):
                let new_type_id = type(data.type_id);
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                return HirForm.var_ref(HirVarData { type_id: new_type_id, name: new_name, symbol_id: new_symbol_id });
            case .binary_op(let data):
                let new_type_id = type(data.type_id);
                let new_left = node(data.left);
                let new_op = data.op;
                let new_right = node(data.right);
                return HirForm.binary_op(HirBinaryOpData { type_id: new_type_id, left: new_left, op: new_op, right: new_right });
            case .unary_op(let data):
                let new_type_id = type(data.type_id);
                let new_op = data.op;
                let new_operand = node(data.operand);
                return HirForm.unary_op(HirUnaryOpData { type_id: new_type_id, op: new_op, operand: new_operand });
            case .ternary(let data):
                let new_type_id = type(data.type_id);
                let new_condition = node(data.condition);
                let new_then_expr = node(data.then_expr);
                let new_else_expr = node(data.else_expr);
                return HirForm.ternary(HirTernaryData { type_id: new_type_id, condition: new_condition, then_expr: new_then_expr, else_expr: new_else_expr });
            case .call(let data):
                let new_type_id = type(data.type_id);
                let new_callee = node(data.callee);
                let new_arguments = Vec<(String?, HirId)>.new();
                for x in data.arguments { new_arguments.push((x.0, node(x.1))); }
                let new_callee_symbol = data.callee_symbol;
                return HirForm.call(HirCallData { type_id: new_type_id, callee: new_callee, arguments: new_arguments, callee_symbol: new_callee_symbol });
            case .method_call(let data):
                let new_type_id = type(data.type_id);
                let new_receiver = node(data.receiver);
                let new_method_name = data.method_name;
                let new_arguments = Vec<(String?, HirId)>.new();
                for x in data.arguments { new_arguments.push((x.0, node(x.1))); }
                let new_method_symbol = data.method_symbol;
                let new_is_static = data.is_static;
                return HirForm.method_call(HirMethodCallData { type_id: new_type_id, receiver: new_receiver, method_name: new_method_name, arguments: new_arguments, method_symbol: new_method_symbol, is_static: new_is_static });
            case .field_access(let data):
                let new_type_id = type(data.type_id);
                let new_object = node(data.object);
                let new_field_name = data.field_name;
                let new_field_symbol = data.field_symbol;
                return HirForm.field_access(HirFieldAccessData { type_id: new_type_id, object: new_object, field_name: new_field_name, field_symbol: new_field_symbol });
            case .subscript(let data):
                let new_type_id = type(data.type_id);
                let new_object = node(data.object);
                let new_indices = Vec<HirId>.new();
                for x in data.indices { new_indices.push(node(x)); }
                return HirForm.subscript(HirSubscriptData { type_id: new_type_id, object: new_object, indices: new_indices });
            case .tuple(let data):
                let new_type_id = type(data.type_id);
                let new_elements = Vec<(String?, HirId)>.new();
                for x in data.elements { new_elements.push((x.0, node(x.1))); }
                return HirForm.tuple(HirTupleData { type_id: new_type_id, elements: new_elements });
            case .array(let data):
                let new_type_id = type(data.type_id);
                let new_elements = Vec<HirId>.new();
                for x in data.elements { new_elements.push(node(x)); }
                let new_element_type = type(data.element_type);
                return HirForm.array(HirArrayData { type_id: new_type_id, elements: new_elements, element_type: new_element_type });
            case .dict(let data):
                let new_type_id = type(data.type_id);
                let new_entries = Vec<(HirId, HirId)>.new();
                for x in data.entries { new_entries.push((node(x.0), node(x.1))); }
                let new_key_type = type(data.key_type);
                let new_value_type = type(data.value_type);
                return HirForm.dict(HirDictData { type_id: new_type_id, entries: new_entries, key_type: new_key_type, value_type: new_value_type });
            case .lambda(let data):
                let new_type_id = type(data.type_id);
                let new_params = Vec<HirId>.new();
                for x in data.params { new_params.push(node(x)); }
                let new_body = node(data.body);
                let new_captures = Vec<SymbolId>.new();
                for x in data.captures { new_captures.push(x); }
                return HirForm.lambda(HirLambdaData { type_id: new_type_id, params: new_params, body: new_body, captures: new_captures });
            case .clone(let data):
                let new_type_id = type(data.type_id);
                let new_value = node(data.value);
                return HirForm.clone(HirCloneData { type_id: new_type_id, value: new_value });
            case .struct_init(let data):
                let new_type_id = type(data.type_id);
                let new_struct_type = type(data.struct_type);
                let new_struct_symbol = data.struct_symbol;
                let new_arguments = Vec<(String?, HirId)>.new();
                for x in data.arguments { new_arguments.push((x.0, node(x.1))); }
                return HirForm.struct_init(HirStructInitData { type_id: new_type_id, struct_type: new_struct_type, struct_symbol: new_struct_symbol, arguments: new_arguments });
            case .enum_construct(let data):
                let new_type_id = type(data.type_id);
                let new_enum_type = type(data.enum_type);
                let new_case_name = data.case_name;
                let new_case_symbol = data.case_symbol;
                let new_payload = Vec<(String?, HirId)>.new();
                for x in data.payload { new_payload.push((x.0, node(x.1))); }
                return HirForm.enum_construct(HirEnumConstructData { type_id: new_type_id, enum_type: new_enum_type, case_name: new_case_name, case_symbol: new_case_symbol, payload: new_payload });
            case .switch_expr(let data):
                let new_type_id = type(data.type_id);
                let new_switch = node(data.switch);
                let new_result_symbol = data.result_symbol;
                return HirForm.switch_expr(HirSwitchExprData { type_id: new_type_id, switch: new_switch, result_symbol: new_result_symbol });
            case .try_expr(let data):
                let new_type_id = type(data.type_id);
                let new_expr = node(data.expr);
                let new_result_type = type(data.result_type);
                var new_error_type: TypeId? = nil; if let x = data.error_type { new_error_type = type(x); }
                return HirForm.try_expr(HirTryExprData { type_id: new_type_id, expr: new_expr, result_type: new_result_type, error_type: new_error_type });
            case .cast(let data):
                let new_type_id = type(data.type_id);
                let new_expr = node(data.expr);
                let new_target_type = type(data.target_type);
                let new_kind = data.kind;
                return HirForm.cast(HirCastData { type_id: new_type_id, expr: new_expr, target_type: new_target_type, kind: new_kind });
            case .type_check(let data):
                let new_type_id = type(data.type_id);
                let new_expr = node(data.expr);
                let new_checked_type = type(data.checked_type);
                return HirForm.type_check(HirTypeCheckData { type_id: new_type_id, expr: new_expr, checked_type: new_checked_type });
            case .optional_some(let data):
                let new_type_id = type(data.type_id);
                let new_value = node(data.value);
                let new_inner_type = type(data.inner_type);
                return HirForm.optional_some(HirOptionalSomeData { type_id: new_type_id, value: new_value, inner_type: new_inner_type });
            case .optional_none(let data):
                let new_type_id = type(data.type_id);
                let new_inner_type = type(data.inner_type);
                return HirForm.optional_none(HirOptionalNoneData { type_id: new_type_id, inner_type: new_inner_type });
            case .optional_match(let data):
                let new_type_id = type(data.type_id);
                let new_scrutinee = node(data.scrutinee);
                let new_inner_type = type(data.inner_type);
                let new_some_binding = data.some_binding;
                let new_some_expr = node(data.some_expr);
                let new_none_expr = node(data.none_expr);
                return HirForm.optional_match(HirOptionalMatchData { type_id: new_type_id, scrutinee: new_scrutinee, inner_type: new_inner_type, some_binding: new_some_binding, some_expr: new_some_expr, none_expr: new_none_expr });
            case .wildcard_pattern: return HirForm.wildcard_pattern();
            case .binding_pattern(let data):
                let new_name = data.name;
                let new_symbol_id = data.symbol_id;
                let new_type_id = type(data.type_id);
                let new_is_mutable = data.is_mutable;
                return HirForm.binding_pattern(HirBindingPatternData { name: new_name, symbol_id: new_symbol_id, type_id: new_type_id, is_mutable: new_is_mutable });
            case .literal_pattern(let data):
                let new_value = data.value;
                let new_type_id = type(data.type_id);
                return HirForm.literal_pattern(HirLiteralPatternData { value: new_value, type_id: new_type_id, upper: data.upper, inclusive: data.inclusive });
            case .tuple_pattern(let data):
                let new_elements = Vec<(String?, HirId)>.new();
                for x in data.elements { new_elements.push((x.0, node(x.1))); }
                let new_type_id = type(data.type_id);
                return HirForm.tuple_pattern(HirTuplePatternData { elements: new_elements, type_id: new_type_id });
            case .enum_case_pattern(let data):
                let new_case_name = data.case_name;
                let new_case_symbol = data.case_symbol;
                let new_payload = Vec<HirId>.new();
                for x in data.payload { new_payload.push(node(x)); }
                let new_enum_type = type(data.enum_type);
                return HirForm.enum_case_pattern(HirEnumCasePatternData { case_name: new_case_name, case_symbol: new_case_symbol, payload: new_payload, enum_type: new_enum_type });
            case .or_pattern(let data):
                let new_patterns = Vec<HirId>.new();
                for x in data.patterns { new_patterns.push(node(x)); }
                let new_type_id = type(data.type_id);
                return HirForm.or_pattern(HirOrPatternData { patterns: new_patterns, type_id: new_type_id });
        }
    }
}
