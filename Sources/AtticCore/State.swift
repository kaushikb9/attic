import Foundation

/// What you decided, per photo. It survives rescans and rebuilds: a photo with
/// a decision is never asked about again unless something new joins it.
public struct Decision: Codable, Hashable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case keep
        /// Marked for deletion. Nothing leaves Photos until "Delete from Photos…".
        case delete
    }
    public enum Source: String, Codable, Sendable {
        case confirm, keepAll = "keep_all", notRetakes = "not_retakes", duplicates, imported
    }
    public var verdict: Verdict
    public var source: Source
    public var at: Date

    public init(_ verdict: Verdict, _ source: Source, at: Date = Date()) {
        // Whole seconds: the JSON file stores ISO 8601 without fractions.
        self.verdict = verdict; self.source = source
        self.at = Date(timeIntervalSince1970: at.timeIntervalSince1970.rounded(.down))
    }
}

public struct BestEvent: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case todo, exported, skipped }
    public var name: String?
    public var picked: [String]?
    public var status: Status = .todo
    /// asset id -> file name inside `folder`
    public var files: [String: String] = [:]
    public var folder: String?
    public init() {}
}

public struct AtticState: Codable, Sendable, Equatable {
    public var decisions: [String: Decision] = [:]
    public var best: [String: BestEvent] = [:]
    /// Off unless you turn it on: naming places sends coordinates to Apple.
    public var namePlaces = false
    /// Cached place names per event id, only when `namePlaces` is on.
    public var placeNames: [String: String] = [:]
    public init() {}

    public var marked: [String] { decisions.filter { $0.value.verdict == .delete }.map(\.key).sorted() }
}

/// JSON file store. One writer: the app.
public final class StateStore: @unchecked Sendable {
    public let url: URL
    public private(set) var state: AtticState

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder.attic.decode(AtticState.self, from: data) {
            state = s
        } else {
            state = AtticState()
        }
    }

    public func update(_ change: (inout AtticState) -> Void) throws {
        var s = state
        change(&s)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.attic.encode(s).write(to: url, options: .atomic)
        state = s
    }

}

extension JSONEncoder {
    static var attic: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var attic: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
