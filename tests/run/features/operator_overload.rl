struct V { var x: i32;
  def __add__(o: V) -> V { V { x: self.x + o.x } }
  def __eq__(o: V) -> Bool { self.x == o.x }
  def __lt__(o: V) -> Bool { self.x < o.x } }
def main() -> i32 { let a = V { x: 40 }; let b = V { x: 2 }; if (a + b) == V { x: 42 } && b < a { return 0; } 1 }
