import std.iterator
struct Queue { var items: [i32]; var at: i32 = 0;
    def next() -> i32? { if self.at >= (self.items.len() as i32) { return nil; } self.at += 1; self.items[self.at - 1] } }
enum Step { case go(i32); case stop; }
def main() -> i32 {
    let q = Queue { items: [1, 2, 3, 4, 5, 6] };
    var sum = 0;
    while let n = q.next() { if n == 2 { continue; } if n == 5 { break; } sum += n; }
    let it = [10, 20, 30].iter();
    var count = 0;
    while let x = it.__next__() { count += x; }
    let steps = [Step.go(2), Step.go(3), Step.stop, Step.go(100)];
    var i = 0; var moved = 0;
    while let .go(k) = steps[i] { moved += k; i += 1; }
    var total = 0; var cursor: i32? = 3;
    while let c = cursor { let add = () -> { total += c; }; add(); cursor = if c > 1 { c - 1 } else { nil }; }
    if sum == 8 && count == 60 && moved == 5 && total == 6 && (q.next() ?? 0) == 6 { return 0; }
    1
}
