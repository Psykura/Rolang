// Typed syntax tree storage for Rolang syntax.
pub import "ast_forms.rl"
pub import "source.rl"

pub struct AstNode {
    pub let id: NodeId;
    pub var span: Span?;
    pub var form: NodeForm;
}

pub struct AstArena {
    let nodes: Vec<AstNode>;
    // Driver metadata stays outside the source AST schema.
    let source_modules: Dict<i32, String>;
    // When recovering, a statement or declaration that fails to parse is recorded
    // here and skipped so one pass reports every syntax error. Speculative parses
    // use arenas without recovery.
    pub var recovering: Bool;
    pub let syntax_errors: Vec<SyntaxError>;
    // Labels of loops (`outer: for ...`) and of the break and continue statements naming them.
    pub let labels: Dict<i32, String> = Dict<i32, String>.new();

    pub static def new(recovering: Bool = false) -> AstArena {
        AstArena { nodes: Vec<AstNode>.new(), source_modules: Dict<i32, String>.with_capacity(16, 0),
                   recovering, syntax_errors: Vec<SyntaxError>.new() }
    }

    pub def len() -> i32 { self.nodes.len() }

    pub def source_module(id: NodeId) -> String? { self.source_modules[id.id] }
    pub def set_source_module(root: NodeId, module: String) -> Void {
        for id in self.preorder(root) { self.source_modules[id.id] = module; }
    }

    pub def add(form: NodeForm, span: Span? = nil) -> NodeId {
        let id = NodeId { id: self.nodes.len() };
        self.nodes.push(AstNode { id, span, form });
        id
    }

    pub def get(id: NodeId) -> AstNode? {
        if id.id < 0 || id.id >= self.nodes.len() { return nil; }
        self.nodes[id.id]
    }

    pub def replace(id: NodeId, form: NodeForm) -> Bool {
        if let node = self.get(id) {
            node.form = form;
            return true;
        }
        false
    }

    pub def preorder(root: NodeId) -> Vec<NodeId> {
        let ordered = Vec<NodeId>.new();
        let pending = Vec<NodeId>.new();
        pending.push(root);
        while pending.len() > 0 {
            let id = pending.pop();
            if let node = self.get(id) {
                ordered.push(id);
                let children = node.form.children();
                var index = children.len() - 1;
                while index >= 0 {
                    pending.push(children[index]);
                    index -= 1;
                }
            }
        }
        ordered
    }
}
