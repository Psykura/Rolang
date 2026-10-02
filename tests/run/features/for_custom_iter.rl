struct R { var cur: i32; var end: i32;
  def __iter__() -> R { self }
  def __next__() -> i32? { if self.cur >= self.end { return nil; } let v = self.cur; self.cur = self.cur + 1; v } }
def main() -> i32 { var s = 0; for n in R { cur: 0, end: 10 } { s += n; } if s == 45 { return 0; } 1 }
