// expect-exit: 20

def get_a() async -> i64 { 10 }
def get_b() async -> i64 { 20 }

def main() async -> i32 {
    let a = await get_a();
    if a > 5 {
        return (await get_b()) as i32;
    }
    return 0;
}
