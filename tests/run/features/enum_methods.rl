enum Op { case add; case sub;
  def apply(a: i32, b: i32) -> i32 { switch self { case .add: a + b; case .sub: a - b; } } }
def main() -> i32 { if Op.add.apply(40, 2) == 42 { return 0; } 1 }
