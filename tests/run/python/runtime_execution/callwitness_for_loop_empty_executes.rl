
struct EmptyIter {
    def __iter__() -> EmptyIter {
        return self;
    }
    
    def __next__() -> i32? {
        return nil;
    }
}

def main() -> i32 {
    var total = 0;
    for x in EmptyIter {} {
        total = total + x;
    }
    return total;
}
