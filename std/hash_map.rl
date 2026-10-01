// Content-based keys using caller-provided hashing and equality.
// Equal keys MUST have equal hashes. Do not mutate key fields used by these
// callbacks while a key is stored, or mutate this map from its callbacks.
import "dict.rl"
import "vec.rl"

pub struct HashEntry<K, V> {
    pub let key: K;
    pub var value: V;
}

pub struct HashMap<K, V> {
    var buckets: Dict<i64, Vec<HashEntry<K, V>>>;
    var hash_key: (K) -> i64;
    var equal_keys: (K, K) -> Bool;
    var count: i64;

    pub static def new(hash_key: (K) -> i64, equal_keys: (K, K) -> Bool) -> HashMap<K, V> {
        return HashMap<K, V> {
            buckets: Dict<i64, Vec<HashEntry<K, V>>>.with_capacity(16, 0),
            hash_key: hash_key, equal_keys: equal_keys, count: 0
        };
    }
    pub def len() -> i64 { return self.count; }
    pub def is_empty() -> Bool { return self.count == 0; }
    pub def get(key: K) -> V? {
        let hash = self.hash_key(key);
        if let bucket = self.buckets.get(hash) {
            for entry in bucket {
                if self.equal_keys(entry.key, key) { return entry.value; }
            }
        }
        return nil;
    }
    pub def contains(key: K) -> Bool {
        if let value = self.get(key) { return true; }
        return false;
    }
    pub def set(key: K, value: V) -> Void {
        let hash = self.hash_key(key);
        if let bucket = self.buckets.get(hash) {
            for entry in bucket {
                if self.equal_keys(entry.key, key) {
                    entry.value = value;
                    return;
                }
            }
            bucket.push(HashEntry<K, V> { key: key, value: value });
        } else {
            let bucket = Vec<HashEntry<K, V>>.new();
            bucket.push(HashEntry<K, V> { key: key, value: value });
            self.buckets.set(hash, bucket);
        }
        self.count = self.count + 1;
    }
    pub def remove(key: K) -> V? {
        let hash = self.hash_key(key);
        if let bucket = self.buckets.get(hash) {
            var i = 0;
            while i < bucket.len() {
                let entry = bucket.get(i);
                if self.equal_keys(entry.key, key) {
                    let value = entry.value;
                    let last = bucket.pop();
                    if i < bucket.len() { bucket.set(i, last); }
                    if bucket.len() == 0 { self.buckets.remove(hash); }
                    self.count = self.count - 1;
                    return value;
                }
                i = i + 1;
            }
        }
        return nil;
    }
    pub def clear() -> Void {
        self.buckets.clear();
        self.count = 0;
    }
    // Snapshot entries; subsequent set/remove calls do not alter this snapshot.
    // Keys and values themselves retain their ordinary reference semantics.
    pub def entries() -> Vec<DictEntry<K, V>> {
        let result = Vec<DictEntry<K, V>>.new();
        for bucket in self.buckets.values() {
            for entry in bucket {
                result.push(DictEntry<K, V> { key: entry.key, value: entry.value });
            }
        }
        return result;
    }
}
