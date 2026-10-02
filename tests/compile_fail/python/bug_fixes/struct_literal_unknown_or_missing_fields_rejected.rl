// expect-error: UNDEFINED_MEMBER: struct 'Point' has no field 'z'

struct Point { var x: i32; var y: i32; }
def main() -> i32 {
    let p = Point { x: 1, z: 2 };
    return p.x;
}
