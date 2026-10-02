def make() -> [i32] { [] }
def count(v: [i32]) -> i32 { v.len() as i32 }
def main() -> i32 { var v: [i32] = []; v.push(40); let w = make(); w.push(2); if v[0] + w[0] == 42 && count([]) == 0 { return 0; } 1 }
