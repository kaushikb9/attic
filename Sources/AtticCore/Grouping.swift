import Foundation

public struct PhotoGroup: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case duplicates, retakes }
    public let id: String
    public let kind: Kind
    /// In the order they were taken.
    public let photos: [Photo]
    public let keeper: String
    public let reason: String
    public let flaws: [String: String]
    public let closeCall: Bool
    /// Ids already decided on in an earlier session ("kept before").
    public let reviewed: Set<String>
    public let timeSpan: TimeInterval
    public var datesDisagree: Bool { timeSpan > Grouping.Tuning().hourS }
}

public enum Grouping {
    /// Set on a real ~650-photo library from the numbers, not by eye: under 0.45 was the same shot at any gap; 0.45
    /// to 0.55 was a retake only within minutes. Near-copies (<0.15 with a
    /// matching perceptual hash) were ~10 pairs; osxphotos found no byte-exact
    /// duplicates.
    public struct Tuning: Sendable {
        public var cut: Float = 0.45
        public var spread: Float = 0.72
        public var nearS: TimeInterval = 300
        public var nearBonus: Float = 0.10
        public var hourS: TimeInterval = 3600
        public var hourBonus: Float = 0.03
        public var dupDistance: Float = 0.15
        public var dupHamming = 5
        public init() {}
    }

    public struct Result: Sendable {
        public var duplicates: [PhotoGroup] = []
        public var retakes: [PhotoGroup] = []
        /// Non-keepers of duplicate groups: the retake pass never sees them.
        public var duplicateLosers: Set<String> = []
        public init() {}
    }

    public static func build(_ all: [Photo], state: AtticState, tuning t: Tuning = Tuning()) -> Result {
        // Shots marked for deletion are out; the rest may still group.
        let photos = all.filter { state.decisions[$0.id]?.verdict != .delete }
        let prints = photos.map(\.features.print)
        let limit = t.cut + t.nearBonus + 0.01
        let pairs = Similarity.nearPairs(prints, limit: max(limit, t.dupDistance))
        var result = Result()

        // 1. Duplicates: near-identical pixels, at any time apart.
        var ds = DisjointSet(photos.count)
        for (i, j, d) in pairs where d <= t.dupDistance
            && Similarity.hamming(photos[i].features.dhash, photos[j].features.dhash) <= t.dupHamming {
            ds.union(i, j)
        }
        var dupOf = Set<Int>()
        for comp in ds.components() where comp.count > 1 {
            let members = comp.map { photos[$0] }
            guard let g = group(.duplicates, members, state) else { continue }
            result.duplicates.append(g)
            for i in comp where photos[i].id != g.keeper { dupOf.insert(i); result.duplicateLosers.insert(photos[i].id) }
        }

        // 2. Retakes among what is left. Time only nudges the distance:
        //    timestamps lie (WhatsApp, other phones, camera clocks).
        func adjusted(_ i: Int, _ j: Int, _ d: Float) -> Float {
            let dt = abs(photos[i].asset.date.timeIntervalSince(photos[j].asset.date))
            return d - (dt < t.nearS ? t.nearBonus : dt < t.hourS ? t.hourBonus : 0)
        }
        var near: [Int: [Int: Float]] = [:]
        var edges: [(Int, Int, Float)] = []
        for (i, j, d) in pairs where !dupOf.contains(i) && !dupOf.contains(j) {
            let a = adjusted(i, j, d)
            near[i, default: [:]][j] = a
            near[j, default: [:]][i] = a
            edges.append((i, j, a))
        }
        let clusters = Clustering.averageLinkage(n: photos.count, edges: edges, cut: t.cut, spread: t.spread) { i, j in
            near[i]?[j] ?? 2  // not a near pair: far apart
        }
        for c in clusters {
            if let g = group(.retakes, c.map { photos[$0] }, state) { result.retakes.append(g) }
        }
        result.duplicates.sort { $0.photos[0].asset.date > $1.photos[0].asset.date }
        result.retakes.sort { $0.photos[0].asset.date > $1.photos[0].asset.date }
        return result
    }

    /// Nil when every photo in it was already decided on.
    static func group(_ kind: PhotoGroup.Kind, _ members: [Photo], _ state: AtticState) -> PhotoGroup? {
        let reviewed = Set(members.map(\.id).filter { state.decisions[$0] != nil })
        guard reviewed.count < members.count else { return nil }
        let photos = members.sorted { $0.asset.date < $1.asset.date }
        let r: Ranking.Result
        var reason: String
        if kind == .duplicates {
            r = duplicateRank(photos)
            let k = photos.firstIndex { $0.id == r.keeper }! + 1
            let smaller = photos.contains { $0.asset.pixels < photos[k - 1].asset.pixels * 0.9 }
            reason = smaller
                ? "Keep #\(k), the full-size original. The others are smaller copies."
                : "These \(photos.count) are the same picture. Keep #\(k)."
        } else {
            r = Ranking.rank(photos)
            reason = r.reason
        }
        let dates = photos.map(\.asset.date)
        let id = kind.rawValue + ":" + (photos.map(\.id).min() ?? "")
        return PhotoGroup(id: id, kind: kind, photos: photos, keeper: r.keeper, reason: reason,
                          flaws: r.flaws, closeCall: kind == .retakes && r.closeCall, reviewed: reviewed,
                          timeSpan: dates.max()!.timeIntervalSince(dates.min()!))
    }

    /// Copies of one picture: keep the favourite, then the edited one, then the
    /// biggest, then the oldest (the original).
    static func duplicateRank(_ photos: [Photo]) -> Ranking.Result {
        let order = photos.sorted {
            let (a, b) = ($0.asset, $1.asset)
            if a.favorite != b.favorite { return a.favorite }
            if a.edited != b.edited { return a.edited }
            if abs(a.pixels - b.pixels) > 0.1 * max(a.pixels, b.pixels) { return a.pixels > b.pixels }
            return a.date < b.date
        }
        let keeper = order[0]
        var flaws: [String: String] = [:]
        for p in order.dropFirst() {
            flaws[p.id] = p.asset.pixels < keeper.asset.pixels * 0.9 ? "a smaller copy" : "a copy"
        }
        return Ranking.Result(order: order.map(\.id), scores: [:], reason: "", flaws: flaws, closeCall: false)
    }
}
