// Standard library: pseudo-random numbers.
//
//     let rng = Random.new();                 // seeded from the OS
//     let roll = rng.int(1, 7);               // 1 to 6
//     let coin = rng.chance(0.5);
//     rng.shuffle(cards);
//     let replay = Random.seeded(42);         // same sequence every run
//
// The generator is xoshiro256** (fast, 256-bit state, not cryptographic).
// Use entropy_u64 for unpredictable values such as tokens.
import "string.rl"
import "vec.rl"
import "range.rl"

pub extern "C" def rt_random_entropy() -> u64;

// 64 bits from the operating system's entropy source.
pub def entropy_u64() -> u64 {
    unsafe { return rt_random_entropy(); }
}

pub struct Random {
    var s0: u64;
    var s1: u64;
    var s2: u64;
    var s3: u64;

    pub static def new() -> Random { Random.seeded(entropy_u64()) }
    // A deterministic generator: equal seeds give equal sequences.
    pub static def seeded(seed: u64) -> Random {
        let mixer = SplitMix { state: seed };
        Random { s0: mixer.next(), s1: mixer.next(), s2: mixer.next(), s3: mixer.next() }
    }

    pub def next_u64() -> u64 {
        let result = rotate_left(self.s1 * 5, 7) * 9;
        let t = self.s1 << 17;
        self.s2 = self.s2 ^ self.s0;
        self.s3 = self.s3 ^ self.s1;
        self.s1 = self.s1 ^ self.s2;
        self.s0 = self.s0 ^ self.s3;
        self.s2 = self.s2 ^ t;
        self.s3 = rotate_left(self.s3, 45);
        result
    }
    pub def next_u32() -> u32 { (self.next_u64() >> 32) as u32 }
    // Uniform in [0, 1).
    pub def next_f64() -> f64 { ((self.next_u64() >> 11) as f64) / 9007199254740992.0 }
    pub def bool() -> Bool { (self.next_u64() >> 63) == 1 }
    // True with probability `probability`.
    pub def chance(probability: f64) -> Bool { self.next_f64() < probability }

    // Uniform in [0, bound); bound must be positive.
    pub def below(bound: u64) -> u64 {
        if bound == 0 { return 0; }
        // Rejecting the low values that would make some results more likely.
        let threshold = (0 - bound) % bound;
        while true {
            let value = self.next_u64();
            if value >= threshold { return value % bound; }
        }
        0
    }
    // Uniform in [low, high); low when the range is empty.
    pub def int(low: i64, high: i64) -> i64 {
        if high <= low { return low; }
        low + (self.below((high - low) as u64) as i64)
    }
    // Uniform in [low, high).
    pub def float(low: f64, high: f64) -> f64 { low + (high - low) * self.next_f64() }

    // A random element, or nil for an empty vector.
    pub def choose<T>(items: Vec<T>) -> T? {
        if items.len() == 0 { return nil; }
        items[self.int(0, items.len() as i64) as i32]
    }
    // Reorders `items` uniformly at random (Fisher–Yates).
    pub def shuffle<T>(items: Vec<T>) -> Void {
        var index = items.len() - 1;
        while index > 0 {
            let other = self.int(0, (index + 1) as i64) as i32;
            let held = items[index];
            items[index] = items[other];
            items[other] = held;
            index -= 1;
        }
    }
    // `count` distinct elements in random order (all of them when count exceeds the length).
    pub def sample<T>(items: Vec<T>, count: i32) -> Vec<T> {
        let pool = items.slice(0..<items.len());
        self.shuffle(pool);
        pool.slice(0..<count)
    }
}

struct SplitMix {
    var state: u64;
    def next() -> u64 {
        self.state = self.state + 11400714819323198485;
        var z = self.state;
        z = (z ^ (z >> 30)) * 13787848793156543929;
        z = (z ^ (z >> 27)) * 10723151780598845931;
        z ^ (z >> 31)
    }
}

def rotate_left(value: u64, count: u64) -> u64 { (value << count) | (value >> (64 - count)) }
