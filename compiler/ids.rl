// Stable identities for compiler nodes, symbols and types.
// Each compilation owns its ID space. Negative SymbolIds are synthetic.
pub struct NodeId {
    pub let id: i32;
    pub def __eq__(other: NodeId) -> Bool { self.id == other.id }
    pub def __ne__(other: NodeId) -> Bool { self.id != other.id }
}
pub struct HirId {
    pub let id: i32;
    pub def __eq__(other: HirId) -> Bool { self.id == other.id }
    pub def __ne__(other: HirId) -> Bool { self.id != other.id }
}
pub struct SymbolId {
    pub let id: i32;
    pub def __eq__(other: SymbolId) -> Bool { self.id == other.id }
    pub def __ne__(other: SymbolId) -> Bool { self.id != other.id }
}
pub struct TypeId {
    pub let id: i32;
    pub def __eq__(other: TypeId) -> Bool { self.id == other.id }
    pub def __ne__(other: TypeId) -> Bool { self.id != other.id }
}
