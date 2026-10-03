import std.io
import std.set
struct Point {
    let x: i32; let y: i32;
    def __eq__(other: Point) -> Bool { self.x == other.x && self.y == other.y }
    def hash() -> u64 { hash_combine(self.x.hash(), self.y.hash()) }
}
struct Tag { let name: String; }
def count<T: Hashable>(items: Vec<T>) -> i32 {
    let seen = Dict<T, Bool>.new();
    for item in items { seen[item] = true; }
    seen.len() as i32
}
def main() -> i32 {
    let grid = Dict<Point, String>.new();
    grid[Point { x: 1, y: 2 }] = "a";
    grid[Point { x: 1, y: 2 }] = "b";
    grid[Point { x: 3, y: 4 }] = "c";
    println(f"{grid.len()} {grid[Point { x: 1, y: 2 }] ?? "?"} {grid.contains(Point { x: 3, y: 4 })} {grid.contains(Point { x: 9, y: 9 })}");
    let tags = Dict<Tag, i32>.new();
    tags[Tag { name: "a" }] = 1; tags[Tag { name: "a" }] = 2;
    println(f"identity keys: {tags.len()}");
    println(f"{count([1, 2, 2, 3])} {count(["x", "y", "x"])} {count([Point { x: 0, y: 0 }, Point { x: 0, y: 0 }])}");
    println(f"{[1, 2] == [1, 2]} {[1, 2] != [2, 1]} {[1, 2].hash() == [1, 2].hash()} {0.0.hash() == (-0.0).hash()}");
    for i in 0..<1000 { grid[Point { x: i, y: -i }] = f"{i}"; }
    println(f"{grid.len()} {grid[Point { x: 500, y: -500 }] ?? "?"} {grid.remove(Point { x: 1, y: 2 }) ?? "?"} {grid.len()}");
    let points = Set<Point>.new();
    points.add(Point { x: 1, y: 1 }); points.add(Point { x: 1, y: 1 });
    println(f"set {points.len()} {points.contains(Point { x: 1, y: 1 })}");
    0
}
