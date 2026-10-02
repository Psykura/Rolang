let ANSWER = BASE + 2;
let BASE = 40;
let WIDE: i64 = 1 << 40;
let RATIO = 1.5;
let NAME = "ro" + "lang";
let ENABLED = !false && ANSWER > 0;
let PICK = ENABLED ? 1 : 2;
let NOTHING: i32? = nil;
let SMALL = 300 as u8;
def limit(x: i32 = ANSWER) -> i32 { x }
def main() -> i32 {
    let label = f"{NAME}-{ANSWER}";
    if ANSWER == 42 && WIDE == 1099511627776 && RATIO * 2.0 == 3.0 && NAME == "rolang" && PICK == 1
        && NOTHING == nil && limit() == 42 && label == "rolang-42" && SMALL == 44 { return 0; }
    1
}
