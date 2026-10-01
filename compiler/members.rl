// Member metadata shared by types.rl and the implementation in member_resolver.rl.
import "ids.rl"
import "frozen.rl"

pub struct FieldInfo {
    pub var name: String;
    pub var type_id: TypeId;
    pub var is_mutable: Bool;
    pub var index: i32;
    pub var visibility: String = "internal";
    pub var source_module: String? = nil;
}
pub struct MethodInfo {
    pub var name: String;
    pub var symbol_id: SymbolId;
    pub var signature: TypeId;
    pub var is_static: Bool = false;
    pub var visibility: String = "pub";
    pub var source_module: String? = nil;
}
pub struct TypeMembers {
    pub let fields: Dict<String, FieldInfo>;
    pub let methods: Dict<String, MethodInfo>;
    pub var generic_param_names: FrozenVec<String>;
    pub static def new() -> TypeMembers {
        TypeMembers { fields: Dict<String, FieldInfo>.with_capacity(16, 1), methods: Dict<String, MethodInfo>.with_capacity(16, 1), generic_param_names: FrozenVec<String>.empty() }
    }
}
