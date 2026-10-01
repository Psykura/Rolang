// Dense type graph cycle analysis, independent of descriptor ABI identities.
// Unknown targets point to TOP; TOP points to every type. Iterative Kosaraju
// finds cycles and propagation through unknown types in O(vertices + edges).
import std.collections

pub def cyclic_capable_ids(num_ids: i32, edges: Dict<i32, Vec<i32>>, conservative: Dict<i32, Bool>) -> Dict<i32, Bool> {
    let cyclic = Dict<i32, Bool>.with_capacity(16, 0);
    if num_ids <= 0 { return cyclic; }
    let top = num_ids;
    let graph = Vec<Vec<i32>>.new(); let reverse = Vec<Vec<i32>>.new();
    let visited = Vec<Bool>.new(); let components = Vec<i32>.new();
    for i in 0..<(num_ids + 1) {
        graph.push(Vec<i32>.new()); reverse.push(Vec<i32>.new()); visited.push(false); components.push(-1);
    }
    for i in 0..<num_ids {
        var unknown = conservative.contains(i);
        if let targets = edges[i] { for target in targets {
            if target < 0 || target >= num_ids { unknown = true; }
            else { graph[i].push(target); reverse[target].push(i); }
        } }
        if unknown { graph[i].push(top); reverse[top].push(i); }
        graph[top].push(i); reverse[i].push(top);
    }
    let order = Vec<i32>.new(); let walk = Vec<(i32, Bool)>.new();
    for start in 0..<(num_ids + 1) {
        if visited[start] { continue; } walk.push((start, false));
        while walk.len() > 0 {
            let item = walk.pop(); let node = item.0;
            if item.1 { order.push(node); continue; }
            if visited[node] { continue; }
            visited[node] = true; walk.push((node, true));
            for next in graph[node] { if !visited[next] { walk.push((next, false)); } }
        }
    }
    let sizes = Vec<i32>.new(); let stack = Vec<i32>.new();
    while order.len() > 0 {
        let start = order.pop(); if components[start] >= 0 { continue; }
        let component = sizes.len(); var size = 0;
        stack.push(start); components[start] = component;
        while stack.len() > 0 {
            let node = stack.pop(); size += 1;
            for next in reverse[node] { if components[next] < 0 { components[next] = component; stack.push(next); } }
        }
        sizes.push(size);
    }
    for node in 0..<num_ids {
        var in_cycle = sizes[components[node]] > 1;
        if !in_cycle { for next in graph[node] { if next == node { in_cycle = true; break; } } }
        if in_cycle { cyclic[node] = true; }
    }
    cyclic
}
