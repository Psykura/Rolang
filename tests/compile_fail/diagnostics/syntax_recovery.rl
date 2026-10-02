// expect-error: expected expression, found ')'
// The first syntax error does not hide later ones.
def first() -> i32 {
    let a = ;
    let b = 2;
    b
}

def second() -> i32 {
    let c = );
    0
}

def main() -> i32 { 0 }
