struct Grid { var w: i32; var cells: [i32];
    def __get__(r: i32, c: i32) -> i32 { self.cells[r * self.w + c] }
    def __set__(r: i32, c: i32, value: i32) -> Void { self.cells[r * self.w + c] = value; } }
struct Log { var last: String; def __set__(key: String, value: String) -> Void { self.last = key + "=" + value; } }
def main() -> i32 {
    let g = Grid { w: 2, cells: [0, 0, 0, 0] };
    g[1, 0] = 40; g[1, 1] = 1; g[1, 1] += 1;
    let log = Log { last: "" }; log["k"] = "v";
    if g[1, 0] + g[1, 1] == 42 && log.last == "k=v" { return 0; }
    1
}
