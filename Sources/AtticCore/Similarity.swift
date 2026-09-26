import Accelerate
import Foundation

public enum Similarity {
    public static func normalised(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return v }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// Euclidean distance between two unit vectors, 0 (same) ... ~1.4.
    public static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(0, 2 - 2 * dot).squareRoot()
    }

    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Every pair (i < j) closer than `limit`. Blocked matrix multiply, so a
    /// 10k-photo library is seconds, not minutes, and memory stays at one block.
    public static func nearPairs(_ prints: [[Float]], limit: Float) -> [(Int, Int, Float)] {
        let n = prints.count
        guard n > 1, let dim = prints.first?.count, dim > 0,
              prints.allSatisfy({ $0.count == dim }) else { return [] }
        let flat = prints.flatMap { $0 }                 // n x dim
        var transposed = [Float](repeating: 0, count: n * dim)  // dim x n
        vDSP_mtrans(flat, 1, &transposed, 1, vDSP_Length(dim), vDSP_Length(n))
        let minDot = 1 - limit * limit / 2               // d < limit  <=>  dot > minDot
        var out: [(Int, Int, Float)] = []
        let block = 256
        var start = 0
        while start < n {
            let rows = min(block, n - start)
            var dots = [Float](repeating: 0, count: rows * n)
            flat.withUnsafeBufferPointer { f in
                vDSP_mmul(f.baseAddress! + start * dim, 1, transposed, 1, &dots, 1,
                          vDSP_Length(rows), vDSP_Length(n), vDSP_Length(dim))
            }
            for r in 0..<rows {
                let i = start + r
                for j in (i + 1)..<n where dots[r * n + j] > minDot {
                    out.append((i, j, max(0, 2 - 2 * dots[r * n + j]).squareRoot()))
                }
            }
            start += rows
        }
        return out
    }
}

/// Union-find over indices 0..<n.
struct DisjointSet {
    private var parent: [Int]
    init(_ n: Int) { parent = Array(0..<n) }
    mutating func find(_ x: Int) -> Int {
        var x = x
        while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
        return x
    }
    mutating func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
    mutating func components() -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for i in parent.indices { byRoot[find(i), default: []].append(i) }
        return Array(byRoot.values)
    }
}

public enum Clustering {
    /// Clusters whose average pairwise distance stays under `cut`, and in which
    /// no two members are further apart than `spread`. Runs inside connected
    /// components of the `edges` graph, so it stays cheap on a large library,
    /// and a chain of look-alikes (a whole beach day) does not collapse into
    /// one group the way single linkage would.
    public static func averageLinkage(n: Int, edges: [(Int, Int, Float)], cut: Float, spread: Float,
                                      distance: (Int, Int) -> Float) -> [[Int]] {
        var ds = DisjointSet(n)
        for (i, j, d) in edges where d < cut { ds.union(i, j) }
        var out: [[Int]] = []
        for comp in ds.components() where comp.count > 1 {
            out += linkage(comp, cut: cut, spread: spread, distance: distance)
        }
        return out.map { $0.sorted() }
    }

    private static func linkage(_ members: [Int], cut: Float, spread: Float,
                                distance: (Int, Int) -> Float) -> [[Int]] {
        let k = members.count
        // Lance-Williams updates: avg and max between live clusters.
        var avg = [Float](repeating: 0, count: k * k)
        var mx = [Float](repeating: 0, count: k * k)
        for a in 0..<k {
            for b in (a + 1)..<k {
                let d = distance(members[a], members[b])
                avg[a * k + b] = d; avg[b * k + a] = d
                mx[a * k + b] = d; mx[b * k + a] = d
            }
        }
        var size = [Int](repeating: 1, count: k)
        var alive = [Bool](repeating: true, count: k)
        var clusters = members.map { [$0] }
        while true {
            var best = cut, pair: (Int, Int)? = nil
            for a in 0..<k where alive[a] {
                for b in (a + 1)..<k where alive[b] {
                    let v = avg[a * k + b]
                    if v < best && mx[a * k + b] < spread { best = v; pair = (a, b) }
                }
            }
            guard let (a, b) = pair else { break }
            for c in 0..<k where alive[c] && c != a && c != b {
                let na = Float(size[a]), nb = Float(size[b])
                let v = (na * avg[a * k + c] + nb * avg[b * k + c]) / (na + nb)
                avg[a * k + c] = v; avg[c * k + a] = v
                let m = max(mx[a * k + c], mx[b * k + c])
                mx[a * k + c] = m; mx[c * k + a] = m
            }
            size[a] += size[b]; alive[b] = false
            clusters[a] += clusters[b]
        }
        return (0..<k).filter { alive[$0] && clusters[$0].count > 1 }.map { clusters[$0] }
    }
}
