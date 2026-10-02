
def main() -> i32 {
    var x: i32;
    var y: i64;
    var z: f64;
    var b: Bool;
    var o: i32?;

    var total: i32 = x;
    total = total + (y as i32);
    total = total + (z as i32);
    if b { total = total + 1; }
    if let v = o { total = total + v; }
    return total;
}
