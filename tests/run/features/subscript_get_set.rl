struct Grid { var v: [i32];
  def __get__(i: i32) -> i32 { self.v[i] }
  def __set__(i: i32, x: i32) -> Void { self.v[i] = x; } }
def main() -> i32 { let g = Grid { v: [0, 0] }; g[1] = 42; if g[1] == 42 { return 0; } 1 }
