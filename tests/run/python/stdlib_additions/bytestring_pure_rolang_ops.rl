
import "bytestring.rl"

def make_abc() -> ByteString {
    var s = ByteString.new();
    s.push(97 as u8);
    s.push(98 as u8);
    s.push(99 as u8);
    return s;
}

def make_bc() -> ByteString {
    var s = ByteString.new();
    s.push(98 as u8);
    s.push(99 as u8);
    return s;
}

def main() -> i32 {
    let abc = make_abc();
    let bc = make_bc();

    if abc.len() != 3 { return 1; }
    if abc.byte_at(0) != (97 as u8) { return 2; }
    if !abc.ends_with(bc) { return 3; }
    if !abc.contains(bc) { return 4; }
    if abc.find(bc) != 1 { return 5; }
    if !abc.substring(1, 2).equals(bc) { return 6; }
    if abc.compare_to(bc) >= 0 { return 7; }

    let doubled = bc.repeat(2);
    if doubled.len() != 4 { return 8; }
    if doubled.byte_at(2) != (98 as u8) { return 9; }

    return 0;
}
