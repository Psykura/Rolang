def classify(n: i32) -> i32 { switch n { case 1 | 2: 10; case 3: 20; default: 30; } }
def main() -> i32 { if classify(1) + classify(2) + classify(9) == 50 && classify(3) == 20 { return 0; } 1 }
