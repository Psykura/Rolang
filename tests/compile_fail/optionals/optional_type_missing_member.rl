// expect-error: Type i32? has no member 'missing'
def main() -> i32 {
    let a = i32?.missing();
    0
}
