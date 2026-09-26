import Foundation

/// Kinds of activity, from Vision's on-device scene labels. Only labels that
/// Vision's VNClassifyImageRequest supports on macOS 26 are listed (checked
/// 2026-09-26 against its 1303 identifiers).
public enum Activity: String, CaseIterable, Codable, Sendable {
    case beach, water, mountains, snow, food, concert, sports, wedding, city, travel, pets, kids, nature

    public var name: String {
        switch self {
        case .beach: "Beach"
        case .water: "On the water"
        case .mountains: "Mountains"
        case .snow: "Snow"
        case .food: "Food"
        case .concert: "Concert"
        case .sports: "Sports"
        case .wedding: "Wedding"
        case .city: "City"
        case .travel: "Travel"
        case .pets: "Pets"
        case .kids: "Kids"
        case .nature: "Nature"
        }
    }

    public var labels: [String] {
        switch self {
        case .beach: ["beach", "shore", "ocean", "island"]
        case .water: ["underwater", "snorkeling", "diving", "swimming", "pool", "lake", "river", "waterfall", "boat"]
        case .mountains: ["mountain", "hill", "hiking", "trail", "camping", "tent", "desert"]
        case .snow: ["snow"]
        case .food: ["food", "dessert", "cake", "drink", "wine", "coffee", "restaurant"]
        case .concert: ["concert", "fireworks"]
        case .sports: ["stadium", "sport", "soccer", "football"]
        case .wedding: ["wedding"]
        case .city: ["cityscape", "street", "bridge", "monument", "museum"]
        case .travel: ["airplane", "airport"]
        case .pets: ["dog", "cat"]
        case .kids: ["baby", "child"]
        case .nature: ["forest", "garden", "flower"]
        }
    }

    public static let allLabels: Set<String> = Set(allCases.flatMap(\.labels))

    public static func of(_ labels: [String: Double], threshold: Double = 0.3) -> Set<Activity> {
        Set(allCases.filter { a in a.labels.contains { (labels[$0] ?? 0) >= threshold } })
    }
}

public struct Event: Identifiable, Hashable, Sendable {
    public let id: String
    public let autoName: String
    public let activity: Activity?
    public let start: Date
    public let end: Date
    public let count: Int
    /// Best first, at most `Events.show`.
    public let candidates: [Photo]
    public let suggested: [String]
    public let center: Location?
    public let away: Bool

    public struct Location: Hashable, Sendable { public let latitude, longitude: Double }
}

public enum Events {
    public static let gap: TimeInterval = 8 * 3600
    public static let tripGap: TimeInterval = 36 * 3600
    public static let tripRadiusKm = 150.0
    public static let minPhotos = 3
    public static let suggest = 3
    public static let show = 12

    /// Photos that may be "best of": no screenshots or documents, nothing
    /// marked for deletion, and only the keeper of each duplicate or retake
    /// group, unless you kept the others on review.
    public static func eligible(_ photos: [Photo], groups: Grouping.Result, state: AtticState) -> [Photo] {
        let losers = groups.duplicateLosers.union(
            groups.retakes.flatMap { g in g.photos.map(\.id).filter { $0 != g.keeper } })
        return photos.filter { p in
            let d = state.decisions[p.id]
            if p.asset.screenshot || p.features.utility || d?.verdict == .delete { return false }
            if losers.contains(p.id) && d?.verdict != .keep { return false }
            return true
        }.sorted { $0.asset.date < $1.asset.date }
    }

    /// ~11 km cells. Home is the cell with the most photos in the library.
    static func cell(_ a: Asset) -> String? {
        guard let la = a.latitude, let lo = a.longitude else { return nil }
        return "\(Int((la * 10).rounded())),\(Int((lo * 10).rounded()))"
    }

    public static func homeCell(_ photos: [Photo]) -> String? {
        var c: [String: Int] = [:]
        for p in photos { if let k = cell(p.asset) { c[k, default: 0] += 1 } }
        return c.max { $0.value < $1.value }?.key
    }

    static func center(_ run: [Photo]) -> Event.Location? {
        let located = run.compactMap { p -> (Double, Double)? in
            guard let la = p.asset.latitude, let lo = p.asset.longitude else { return nil }
            return (la, lo)
        }
        guard !located.isEmpty else { return nil }
        let n = Double(located.count)
        return .init(latitude: located.map(\.0).reduce(0, +) / n, longitude: located.map(\.1).reduce(0, +) / n)
    }

    static func km(_ a: Event.Location, _ b: Event.Location) -> Double {
        let r = 6371.0, p = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * p, dLon = (b.longitude - a.longitude) * p
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * p) * cos(b.latitude * p) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }

    static func isAway(_ run: [Photo], home: String?) -> Bool {
        let cells = run.compactMap { cell($0.asset) }
        guard !cells.isEmpty else { return false }
        return cells.filter { $0 != home }.count * 2 > cells.count
    }

    public static func split(_ photos: [Photo], home: String?) -> [[Photo]] {
        var runs: [[Photo]] = []
        for p in photos {
            if let last = runs.last?.last, p.asset.date.timeIntervalSince(last.asset.date) <= gap {
                runs[runs.count - 1].append(p)
            } else {
                runs.append([p])
            }
        }
        // Days away in one region become one trip.
        var merged: [[Photo]] = []
        for run in runs {
            if let prev = merged.last, let a = center(prev), let b = center(run),
               run[0].asset.date.timeIntervalSince(prev.last!.asset.date) <= tripGap,
               isAway(prev, home: home), isAway(run, home: home), km(a, b) <= tripRadiusKm {
                merged[merged.count - 1] += run
            } else {
                merged.append(run)
            }
        }
        return merged.filter { $0.count >= minPhotos }
    }

    /// The activity most of the event shows, if one clearly does.
    public static func activity(_ run: [Photo]) -> Activity? {
        var count: [Activity: Int] = [:]
        for p in run { for a in Activity.of(p.features.labels) { count[a, default: 0] += 1 } }
        guard let (a, n) = count.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }),
              Double(n) >= 0.3 * Double(run.count) else { return nil }
        return a
    }

    public static func dates(_ a: Date, _ b: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_GB"); f.timeZone = calendar.timeZone
        func fmt(_ d: Date, _ p: String) -> String { f.dateFormat = p; return f.string(from: d) }
        if calendar.isDate(a, inSameDayAs: b) { return fmt(a, "d MMM yyyy") }
        let sameMonth = calendar.component(.month, from: a) == calendar.component(.month, from: b)
            && calendar.component(.year, from: a) == calendar.component(.year, from: b)
        if sameMonth { return "\(fmt(a, "d"))–\(fmt(b, "d MMM yyyy"))" }
        return "\(fmt(a, "d MMM")) – \(fmt(b, "d MMM yyyy"))"
    }

    public static func build(_ photos: [Photo], groups: Grouping.Result, state: AtticState,
                             calendar: Calendar = .current) -> [Event] {
        let home = homeCell(photos)
        var out: [Event] = []
        for run in split(eligible(photos, groups: groups, state: state), home: home) {
            let first = run[0].asset, last = run[run.count - 1].asset
            let id = "\(Self.dayKey(first.date, calendar)).\(first.id.prefix(8))"
            let act = activity(run)
            let when = dates(first.date, last.date, calendar: calendar)
            let place = state.namePlaces ? state.placeNames[id] : nil
            let name = [place ?? act?.name, when].compactMap { $0 }.joined(separator: " · ")
            let ranked = Ranking.rank(run)
            let byId = Dictionary(uniqueKeysWithValues: run.map { ($0.id, $0) })
            let cands = ranked.order.prefix(show).compactMap { byId[$0] }
            out.append(Event(id: id, autoName: name, activity: act, start: first.date, end: last.date,
                             count: run.count, candidates: cands,
                             suggested: cands.prefix(suggest).map(\.id), center: center(run),
                             away: isAway(run, home: home)))
        }
        return out.sorted { $0.start > $1.start }
    }

    static func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// Folder and file naming for the best-of export, and the one rule that
/// matters: nothing is written outside the best-of folder.
public enum ExportNaming {
    public static let maxEdge = 2400

    public static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
        let parts = folded.lowercased().split { !($0.isLetter || $0.isNumber) || !$0.isASCII }
        return parts.isEmpty ? "event" : parts.joined(separator: "-")
    }

    public static func folder(start: Date, name: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: start)
        return String(format: "%04d-%02d-", c.year!, c.month!) + slug(name)
    }

    public static func file(date: Date, id: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02d-%02d%02d%02d-", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
            + String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8)).lowercased() + ".jpg"
    }

    public struct Outside: Error, CustomStringConvertible {
        public let path: String
        public var description: String { "Refusing to write outside the best-of folder: \(path)" }
    }

    public static func inside(_ root: URL, _ url: URL) throws -> URL {
        // standardized removes "..", so "best-of/../x" is caught.
        let r = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p == r || p.hasPrefix(r + "/") else { throw Outside(path: p) }
        return url
    }
}
