struct Item { var value: i32; }

def increment(value: i32?) -> i32? {
    let n = value?;
    n + 1
}

def read(value: Item?) -> i32 {
    guard let item = value else { return 0; }
    item.value
}

def main() -> i32 {
    let item: Item? = Item { value: 42 };
    if let unexpected = increment(nil) { return 2; }
    if (increment(41) ?? 0) == 42 && read(item) == 42
        && (item?.value ?? 0) == 42 { return 0; }
    1
}
