import Foundation

/// Picks a keeper in a set of similar photos and says why, in plain words.
///
/// Scores are relative to the set: "sharpest of these six" is what matters.
/// A signal nobody in the set has (no faces) contributes nothing, so it cannot
/// drag anyone down. Each signal has a minimum spread (`floor`), so a 1%
/// sharpness wobble never decides a keeper.
public enum Ranking {
    public enum Signal: String, CaseIterable, Sendable {
        case resolution, faces, aesthetic, sharpness, exposure

        var weight: Double {
            switch self {
            case .resolution: 1.5   // a WhatsApp re-save never beats its original
            case .faces: 1.2
            case .aesthetic: 1.0
            case .sharpness: 0.8
            case .exposure: 0.5
            }
        }
        var floor: Double {
            switch self {
            case .resolution: log(4)   // 2x on each side
            case .faces: 0.3
            case .aesthetic: 0.3
            case .sharpness: log(2)
            case .exposure: 0.1
            }
        }
        public var win: String {
            switch self {
            case .resolution: "it is the full-size original"
            case .faces: "the faces are clearest"
            case .aesthetic: "it is the best composed"
            case .sharpness: "it is the sharpest"
            case .exposure: "it is the best exposed"
            }
        }
        public var flaw: String {
            switch self {
            case .resolution: "a smaller copy"
            case .faces: "a face is blurred or eyes closed"
            case .aesthetic: "weaker framing"
            case .sharpness: "blurrier"
            case .exposure: "blown or crushed exposure"
            }
        }
    }

    public static let closeMargin = 0.12
    static let favouriteBonus = 2.0   // beats any signal (max 1)
    static let editedBonus = 0.15

    public struct Result: Sendable {
        public var order: [String]          // best first
        public var scores: [String: Double]
        public var keeper: String { order[0] }
        public var reason: String
        public var flaws: [String: String]  // non-keepers only
        public var closeCall: Bool
    }

    static func raw(_ s: Signal, _ p: Photo, maxFaces: Int) -> Double? {
        let f = p.features
        switch s {
        case .resolution: return log(p.asset.pixels)
        case .faces:
            guard maxFaces > 0 else { return nil }
            // Someone missing from the frame counts as a bad face.
            return (f.faceMin ?? 0) * Double(f.faces) / Double(maxFaces)
        case .aesthetic: return f.aesthetic
        case .sharpness: return log1p(f.sharpness)
        case .exposure: return -f.clipped
        }
    }

    public static func signals(_ photos: [Photo]) -> [Signal: [Double?]] {
        let maxFaces = photos.map(\.features.faces).max() ?? 0
        var out: [Signal: [Double?]] = [:]
        for s in Signal.allCases {
            let vals = photos.map { raw(s, $0, maxFaces: maxFaces) }
            let present = vals.compactMap { $0 }
            guard present.count >= 2, let lo = present.min(), let hi = present.max(), hi - lo > 1e-9 else {
                out[s] = Array(repeating: nil, count: photos.count); continue
            }
            out[s] = vals.map { $0.map { ($0 - lo) / max(hi - lo, s.floor) } }
        }
        return out
    }

    public static func rank(_ photos: [Photo]) -> Result {
        precondition(!photos.isEmpty)
        let sig = signals(photos)
        let active = Signal.allCases.filter { s in sig[s]!.contains { $0 != nil } }
        let totalW = max(active.reduce(0) { $0 + $1.weight }, 1)
        var scores: [String: Double] = [:]
        for (i, p) in photos.enumerated() {
            var s = active.reduce(0.0) { acc, sg in acc + sg.weight * (sig[sg]![i] ?? 0) } / totalW
            if p.asset.favorite { s += favouriteBonus }
            if p.asset.edited { s += editedBonus }
            scores[p.id] = s
        }
        let orderIdx = photos.indices.sorted {
            scores[photos[$0].id]! != scores[photos[$1].id]!
                ? scores[photos[$0].id]! > scores[photos[$1].id]!
                : photos[$0].asset.date < photos[$1].asset.date
        }
        let keep = orderIdx[0]
        let runner = orderIdx.count > 1 ? orderIdx[1] : keep
        var flaws: [String: String] = [:]
        for i in photos.indices where i != keep {
            if let worst = edges(sig, keep, i).first { flaws[photos[i].id] = worst.flaw }
        }
        let margin = scores[photos[keep].id]! - scores[photos[runner].id]!
        return Result(order: orderIdx.map { photos[$0].id }, scores: scores,
                      reason: reason(photos, sig, keep, runner),
                      flaws: flaws,
                      closeCall: photos.count > 1 && margin < closeMargin && !photos[keep].asset.favorite)
    }

    /// Signals where `a` clearly beats `b`, biggest weighted gap first.
    static func edges(_ sig: [Signal: [Double?]], _ a: Int, _ b: Int) -> [Signal] {
        Signal.allCases.compactMap { s -> (Double, Signal)? in
            guard let va = sig[s]![a], let vb = sig[s]![b], va - vb > 0.15 else { return nil }
            return (s.weight * (va - vb), s)
        }.sorted { $0.0 > $1.0 }.map(\.1)
    }

    static func reason(_ photos: [Photo], _ sig: [Signal: [Double?]], _ keep: Int, _ runner: Int) -> String {
        if photos[keep].asset.favorite { return "Keep #\(keep + 1): you marked it as a favourite." }
        let wins = Array(edges(sig, keep, runner).prefix(2))
        if wins.isEmpty {
            return "Keep #\(keep + 1). These \(photos.count) are near-identical, so any one will do."
        }
        return "Keep #\(keep + 1): " + wins.map(\.win).joined(separator: " and ") + ". #\(runner + 1) is the next best."
    }
}
