
struct Holder { var value: String; }
def make() -> Holder { return Holder { value: "ke" + "pt" }; }
def main() -> i32 {
    unsafe {
        let size = rt_string_len(make().value);
        return (size as i32) - 4;
    }
}
