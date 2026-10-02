struct S { var a: i64; }
def main() -> i32 {
    let s = size_of(i64); let al = align_of(i64); let t1 = type_id(S); let t2 = type_id(i32);
    let d = drop_of(S); let c = clone_of(S);
    if s == 8 && al == 8 && t1 != t2 { return 0; }
    1
}
