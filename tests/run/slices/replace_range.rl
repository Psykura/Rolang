def show(v: [i32]) -> String { var out = ""; for x in v { out = out + f"{x},"; } out }
struct Item { var id: i32; }
def main() -> i32 {
    var v = [1, 2, 3, 4, 5];
    v[1..<3] = [20, 30];
    if show(v) != "1,20,30,4,5," { return 1; }
    v[1...2] = [9];
    if show(v) != "1,9,4,5," { return 2; }
    v[..<1] = [7, 7, 7];
    if show(v) != "7,7,7,9,4,5," { return 3; }
    v[4...] = [];
    if show(v) != "7,7,7,9," { return 4; }
    v[2..<2] = [0];
    if show(v) != "7,7,0,7,9," { return 5; }
    v[...] = v;
    if show(v) != "7,7,0,7,9," { return 6; }
    let items = [Item { id: 1 }, Item { id: 2 }];
    items[0..<1] = [Item { id: 5 }, Item { id: 6 }];
    if items.len() != 3 || items[1].id != 6 || items[2].id != 2 { return 7; }
    0
}
