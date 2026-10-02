struct M { var d: [i32];
  def __get__(r: i32, c: i32) -> i32 { self.d[r * 2 + c] } }
def main() -> i32 { let m = M { d: [0, 1, 2, 42] }; if m[1, 1] == 42 { return 0; } 1 }
