// Stable, zero-based string IDs for a single compiler session.
import "dict.rl"
import "vec.rl"
import "string.rl"

pub struct StringInterner {
    var ids: Dict<String, i32>;
    var strings: Vec<String>;

    pub static def new() -> StringInterner {
        return StringInterner {
            ids: Dict<String, i32>.with_capacity(16, 1),
            strings: Vec<String>.new()
        };
    }
    pub def intern(text: String) -> i32 {
        if let id = self.ids.get(text) { return id; }
        let id = self.strings.len();
        self.strings.push(text);
        self.ids.set(text, id);
        return id;
    }
    pub def lookup(text: String) -> i32? { return self.ids.get(text); }
    pub def resolve(id: i32) -> String? {
        if id < 0 || id >= self.strings.len() { return nil; }
        return self.strings.get(id);
    }
    pub def len() -> i32 { return self.strings.len(); }
}
