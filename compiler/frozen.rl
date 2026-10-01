// An immutable sequence for compiler metadata.
// Copy the incoming vector; do not expose its mutable storage. Element types
// used in intern keys must themselves be immutable (IDs and metadata records).
pub struct FrozenVec<T> {
    let storage: Vec<T>;

    pub static def new(values: Vec<T>) -> FrozenVec<T> {
        let storage = Vec<T>.new();
        for value in values { storage.push(value); }
        FrozenVec<T> { storage }
    }
    pub static def empty() -> FrozenVec<T> { FrozenVec<T>.new(Vec<T>.new()) }
    pub def len() -> i32 { self.storage.len() }
    pub def get(index: i32) -> T { self.storage[index] }
    pub def __iter__() -> FrozenIter<T> {
        FrozenIter<T> { storage: self.storage, index: 0 }
    }
    pub def to_vec() -> Vec<T> {
        let result = Vec<T>.new();
        for value in self { result.push(value); }
        result
    }
    pub def map<U>(transform: (T) -> U) -> FrozenVec<U> {
        let result = Vec<U>.new();
        for value in self { result.push(transform(value)); }
        FrozenVec<U>.new(result)
    }
}

pub struct FrozenIter<T> {
    let storage: Vec<T>;
    var index: i32;

    pub def __next__() -> T? {
        if self.index >= self.storage.len() { return nil; }
        let value = self.storage[self.index];
        self.index += 1;
        value
    }
}
