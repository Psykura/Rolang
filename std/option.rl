// Rolang's optional type is T?. Helpers compose it without forced unwrapping.
pub def option_map<T, U>(value: T?, transform: (T) -> U) -> U? {
    guard let item = value else { return nil; }
    return transform(item);
}

pub def option_and_then<T, U>(value: T?, transform: (T) -> U?) -> U? {
    guard let item = value else { return nil; }
    return transform(item);
}

pub def option_filter<T>(value: T?, predicate: (T) -> Bool) -> T? {
    guard let item = value else { return nil; }
    guard predicate(item) else { return nil; }
    return item;
}
