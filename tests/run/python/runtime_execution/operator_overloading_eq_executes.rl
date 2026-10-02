
struct Box {
    var value: i32;
}

extension Box {
    pub def __eq__(other: Box) -> Bool {
        return self.value == other.value;
    }
}

def main() -> i32 {
    let a = Box { value: 5 };
    let b = Box { value: 5 };
    let c = Box { value: 7 };
    if a == b {
        if a == c {
            return 1;
        }
        return 0;
    }
    return 2;
}
