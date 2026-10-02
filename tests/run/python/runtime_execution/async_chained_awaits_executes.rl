// expect-exit: 42

def step1() async -> i64 { 10 }
def step2(x: i64) async -> i64 { x + 32 }

def main() async -> i32 {
    let a = await step1();
    let b = await step2(a);
    b as i32
}
