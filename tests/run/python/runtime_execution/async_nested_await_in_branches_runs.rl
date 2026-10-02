// expect-exit: 50

def get_a() async -> i64 { 10 }
def get_b() async -> i64 { 20 }
def get_c() async -> i64 { 30 }

def main() async -> i32 {
    let v = await get_a();
    if v > 5 {
        let extra = await get_b();
        return (extra + (await get_c())) as i32;
    }
    return 0;
}
