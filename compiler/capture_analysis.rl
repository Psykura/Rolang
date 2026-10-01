pub import "hir.rl"
pub import "types.rl"
pub import "symbols.rl"

pub struct CaptureInfo { pub let symbol_id: SymbolId; pub let name: String; pub let type_id: TypeId; pub let is_mutable: Bool; }
pub def analyze_captures(hir: HirArena, lambda: HirLambdaData, outer: Dict<i32, TypeId>, symbols: SymbolTable) -> Vec<CaptureInfo> {
    let references = Dict<i32, Bool>.with_capacity(16, 0); let declared = Dict<i32, Bool>.with_capacity(16, 0);
    for param in lambda.params { if let node = hir.get(param) { switch node.form { case .param(let data): declared[data.symbol_id.id] = true; default: {} } } }
    for id in hir.preorder(lambda.body) { if let node = hir.get(id) { switch node.form {
        case .var_ref(let data): references[data.symbol_id.id] = true;
        case .var_decl(let data): declared[data.symbol_id.id] = true;
        case .param(let data): declared[data.symbol_id.id] = true;
        case .binding_pattern(let data): declared[data.symbol_id.id] = true;
        case .optional_match(let data): declared[data.some_binding.id] = true;
        case .switch_expr(let data): declared[data.result_symbol.id] = true;
        default: {}
    } } }
    let ids = Vec<i32>.new();
    for entry in references.entries() { if !declared.contains(entry.key) && outer.contains(entry.key) { ids.push(entry.key); } }
    var i = 1; while i < ids.len() { var j = i; while j > 0 && ids[j] < ids[j-1] {
        let old = ids[j]; ids[j] = ids[j-1]; ids[j-1] = old; j -= 1;
    } i += 1; }
    let out = Vec<CaptureInfo>.new();
    for id in ids { if let symbol = symbols.get_symbol(SymbolId { id }) { switch symbol.kind {
        case .variable | .parameter: if let type_id = outer[id] { out.push(CaptureInfo { symbol_id: symbol.id,
            name: symbol.name, type_id, is_mutable: symbol.is_mutable }); }
        default: {}
    } } } out
}
