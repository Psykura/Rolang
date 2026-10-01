// Arena-owned, explicitly typed HIR. AST and HIR identities cannot be mixed.
pub import "hir_forms.rl"
pub struct HirNode {
    pub let id: HirId;
    pub var form: HirForm;
}
pub struct HirArena {
    let nodes: Vec<HirNode>;
    pub static def new() -> HirArena { HirArena { nodes: Vec<HirNode>.new() } }
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
