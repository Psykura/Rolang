// Arena-owned, explicitly typed HIR. AST and HIR identities cannot be mixed.
pub import "hir_forms.rl"
pub struct HirNode {
    pub let id: HirId;
    pub var form: HirForm;
}
// Source position of a HIR statement or function, for debug information.
pub struct HirLocation { pub let file: String; pub let line: i32; pub let column: i32; }
pub struct HirArena {
    let nodes: Vec<HirNode>;
    let locations: Dict<i32, HirLocation>;
    // Explicit type arguments of generic calls (`f<i32>(x)`), by call node.
    pub let type_arguments: Dict<i32, Dict<String, TypeId>>;
    // Generic extension methods to instantiate per type (see require_hash_methods).
    pub let required_methods: Vec<(TypeId, SymbolId)>;
    pub static def new() -> HirArena { HirArena { nodes: Vec<HirNode>.new(), locations: Dict<i32, HirLocation>.new(), type_arguments: Dict<i32, Dict<String, TypeId>>.new(), required_methods: Vec<(TypeId, SymbolId)>.new() } }
    pub def location(id: HirId) -> HirLocation? { self.locations[id.id] }
    pub def set_location(id: HirId, location: HirLocation?) -> Void { if let known = location { self.locations[id.id] = known; } }
    // Gives `copy` the location of `original`, for nodes cloned by later passes.
    pub def copy_location(original: HirId, copy: HirId) -> HirId { self.set_location(copy, self.location(original)); copy }
    pub def len() -> i32 { self.nodes.len() }
    pub def add(form: HirForm) -> HirId {
        let id = HirId { id: self.nodes.len() }; self.nodes.push(HirNode { id, form }); id
    }
    pub def get(id: HirId) -> HirNode? {
        if id.id < 0 || id.id >= self.nodes.len() { return nil; }
        self.nodes[id.id]
    }
    pub def replace(id: HirId, form: HirForm) -> Bool {
        if let node = self.get(id) { node.form = form; return true; } false
    }
    pub def preorder(root: HirId) -> Vec<HirId> {
        let out = Vec<HirId>.new(); let stack = Vec<HirId>.new(); stack.push(root);
        while stack.len() > 0 {
            let index = stack.len() - 1; let id = stack[index]; stack.pop();
            out.push(id);
            if let node = self.get(id) { let children = node.form.children(); var i = children.len(); while i > 0 { i -= 1; stack.push(children[i]); } }
        }
        out
    }
    pub def type_of(id: HirId, fallback: TypeId) -> TypeId {
        if let node = self.get(id) { return node.form.type_id() ?? fallback; } fallback
    }
}
