import std.io
import std.random
def main() -> i32 {
    // xoshiro256** seeded through SplitMix64 matches the reference sequence.
    let rng = Random.seeded(42);
    println(f"{rng.next_u64()} {rng.next_u64()} {rng.next_u64()}");
    let dice = Random.seeded(7);
    let counts = [0, 0, 0, 0, 0, 0];
    for i in 0..<60000 { counts[(dice.int(1, 7) - 1) as i32] += 1; }
    var fair = true;
    for count in counts { if count < 9500 || count > 10500 { fair = false; } }
    let deck = [1, 2, 3, 4, 5, 6, 7, 8];
    dice.shuffle(deck);
    var sum = 0; for card in deck { sum += card; }
    let picked = dice.sample(deck, 3);
    var inside = true; for value in picked { if value < 1 || value > 8 { inside = false; } }
    var floats = true;
    for i in 0..<1000 { let f = dice.next_f64(); let g = dice.float(-2.0, 2.0); if f < 0.0 || f >= 1.0 || g < -2.0 || g >= 2.0 { floats = false; } }
    println(f"{fair} {sum} {picked.len()} {inside} {floats} {dice.choose(Vec<i32>.new()) == nil} {dice.int(5, 5)}");
    println(f"{Random.seeded(9).next_u64() == Random.seeded(9).next_u64()} {Random.new().next_u64() != Random.new().next_u64()}");
    0
}
