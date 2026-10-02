// expect-error: uses Self, the unknown concrete type behind the value
protocol Ranked { def beats(other: Self) -> Bool; }
struct Card: Ranked { let value: i32; def beats(other: Card) -> Bool { self.value > other.value } }
def main() -> i32 { let card: any Ranked = Card { value: 1 }; if card.beats(card) { return 1; } 0 }
