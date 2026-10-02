// `Self` in a requirement is the conforming type; operator requirements make
// the operators available on bounded type parameters.
protocol Addable { def __add__(other: Self) -> Self; }
protocol Ranked { def beats(other: Self) -> Bool; }
struct Money: Addable { let cents: i64; def __add__(other: Money) -> Money { Money { cents: self.cents + other.cents } } }
struct Card: Ranked { let value: i32; def beats(other: Card) -> Bool { self.value > other.value } }
protocol Shape { def area() -> i32; }
struct Square: Shape { let side: i32; def area() -> i32 { self.side * self.side } }

def total<T: Addable>(items: Vec<T>, zero: T) -> T {
    var sum = zero;
    for item in items { sum = sum + item; }
    sum
}
def winner<T: Ranked>(a: T, b: T) -> T { if b.beats(a) { return b; } a }

// A method's `where` bounds its type's parameter.
struct Shelf<T> {
    let items: Vec<T>;
    def total_area() -> i32 where T: Shape { var sum = 0; for item in self.items { sum += item.area(); } sum }
}

def main() -> i32 {
    if total([1, 2, 3], 0) != 6 || total([0.5, 0.25], 0.0) != 0.75 { return 1; }
    if total([Money { cents: 150 }, Money { cents: 275 }], Money { cents: 0 }).cents != 425 { return 2; }
    if winner(Card { value: 3 }, Card { value: 9 }).value != 9 { return 3; }
    if Shelf<Square> { items: [Square { side: 2 }, Square { side: 3 }] }.total_area() != 13 { return 4; }
    0
}
