import CoreLocation
import Foundation
import AtticCore
import Observation

/// Everything the window does, with no SwiftUI in it, so tests drive the same
/// code the buttons do.
@MainActor @Observable
public final class AppModel {
    public enum Phase: Equatable { case starting, denied, analyzing(Int, Int), ready }
    public enum Section: String, CaseIterable, Identifiable, Hashable {
        case duplicates, retakes, bestOf, marked
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .duplicates: "Duplicates"
            case .retakes: "Retakes"
            case .bestOf: "Best of"
            case .marked: "Marked for deletion"
            }
        }
    }
    public enum EventFilter: String, CaseIterable, Identifiable { case todo, exported, skipped; public var id: String { rawValue } }

    public var phase: Phase = .starting
    public var section: Section = .duplicates
    public var eventFilter: EventFilter = .todo
    public private(set) var photos: [String: Photo] = [:]
    public private(set) var grouping = Grouping.Result()
    public private(set) var events: [Event] = []
    public private(set) var unavailable = 0
    /// One line for the person using it: what happened, or what went wrong and how to fix it.
    public var message: String?
    public private(set) var working: Set<String> = []
    public private(set) var skippedGroups: Set<String> = []

    private var keepEdits: [String: Set<String>] = [:]
    private var pickEdits: [String: Set<String>] = [:]
    /// Every action on a group is one ⌘Z: decisions restore what was there,
    /// a skip brings the group back.
    private enum Undo { case decisions([String: Decision?]), skip(String) }
    private var undoStack: [Undo] = []

    public let source: PhotoSource
    public let store: StateStore
    public let analyzer: Analyzer
    public let exporter: Exporter
    let summaryURL: URL?

    public init(source: PhotoSource, store: StateStore, analyzer: Analyzer, exporter: Exporter, summaryURL: URL? = nil) {
        self.source = source; self.store = store; self.analyzer = analyzer; self.exporter = exporter
        self.summaryURL = summaryURL
        self.state = store.state
    }

    /// The only way AppModel changes saved state: write, then refresh the observed copy.
    func save(_ change: (inout AtticState) -> Void) throws {
        defer { state = store.state }
        try store.update(change)
    }

    /// An observed copy of `store.state`. StateStore is a plain class, so views
    /// reading it directly never redrew (the Marked page said "Nothing marked"
    /// while the sidebar said 5). Every write goes through `save`.
    public private(set) var state = AtticState()

    // MARK: lifecycle

    public func start() async {
        guard await source.requestAccess() == .granted else { phase = .denied; return }
        await rescan()
    }

    public func rescan() async {
        let assets = await source.loadAssets()
        phase = .analyzing(0, assets.count)
        let result = await analyzer.analyze(assets, source: source) { done, total in
            Task { @MainActor in if case .analyzing = self.phase { self.phase = .analyzing(done, total) } }
        }
        photos = Dictionary(uniqueKeysWithValues: result.photos.map { ($0.id, $0) })
        unavailable = result.unavailable
        rebuild()
        phase = .ready
        writeSummary()
    }

    public func rebuild() {
        let all = Array(photos.values)
        grouping = Grouping.build(all, state: state)
        events = Events.build(all, groups: grouping, state: state)
        let live = Set((grouping.duplicates + grouping.retakes).map(\.id))
        keepEdits = keepEdits.filter { live.contains($0.key) }
    }

    /// Counts only, for agents checking a run without looking at photos.
    func writeSummary() {
        guard let summaryURL else { return }
        let s: [String: Int] = ["photos": photos.count, "unavailable": unavailable,
                                "duplicate_groups": grouping.duplicates.count, "retake_groups": grouping.retakes.count,
                                "events": events.count, "marked": state.marked.count,
                                "decisions": state.decisions.count]
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: summaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(s).write(to: summaryURL, options: .atomic)
    }

    // MARK: groups

    public func visibleGroups(_ kind: PhotoGroup.Kind) -> [PhotoGroup] {
        (kind == .duplicates ? grouping.duplicates : grouping.retakes).filter { !skippedGroups.contains($0.id) }
    }

    public func keepSet(_ g: PhotoGroup) -> Set<String> {
        keepEdits[g.id] ?? Set([g.keeper]).union(g.reviewed.filter { state.decisions[$0]?.verdict == .keep })
    }

    public func toggle(_ g: PhotoGroup, _ id: String) {
        var s = keepSet(g)
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        keepEdits[g.id] = s
    }

    /// Keeps what is ticked and marks the rest for deletion. Nothing leaves
    /// Photos until "Delete from Photos…".
    public func confirm(_ g: PhotoGroup) {
        let keep = keepSet(g)
        let n = g.photos.count - keep.count
        record(g.photos.map { ($0.id, keep.contains($0.id) ? .keep : .delete) },
               g.kind == .duplicates ? .duplicates : .confirm,
               done: n > 0 ? "Marked \(n) for deletion" : "Kept all \(g.photos.count)")
    }

    public func keepAll(_ g: PhotoGroup) {
        record(g.photos.map { ($0.id, .keep) }, .keepAll, done: "Kept all \(g.photos.count)")
    }

    /// Keeps all, and records that the grouping was wrong (tuning data).
    public func notRetakes(_ g: PhotoGroup) {
        record(g.photos.map { ($0.id, .keep) }, .notRetakes, done: "Kept all \(g.photos.count), not retakes")
    }

    /// Ask again next launch.
    public func skip(_ g: PhotoGroup) {
        skippedGroups.insert(g.id)
        undoStack.append(.skip(g.id))
        message = "Skipped until next launch · ⌘Z undoes"
    }

    /// `done` is the one line saying what happened. A group leaving the view
    /// says so, because a stray key can do it unseen (2026-09-26).
    private func record(_ items: [(String, Decision.Verdict)], _ source: Decision.Source, done: String) {
        var before: [String: Decision?] = [:]
        for (id, _) in items { before[id] = state.decisions[id] }
        do {
            try save { s in for (id, v) in items { s.decisions[id] = Decision(v, source) } }
            undoStack.append(.decisions(before))
            message = "\(done) · ⌘Z undoes"
        } catch {
            message = "Not saved: \(error.localizedDescription). Check that ~/Library/Application Support/Attic is writable."
        }
        rebuild()
        writeSummary()
    }

    /// Test hook: forget photos as if deleted, without touching the source.
    func debugDrop(_ ids: [String]) { for id in ids { photos[id] = nil }; rebuild() }

    public var canUndo: Bool { !undoStack.isEmpty }

    public func undo() {
        guard let last = undoStack.popLast() else { return }
        switch last {
        case let .decisions(before): try? save { s in for (id, d) in before { s.decisions[id] = d } }
        case let .skip(id): skippedGroups.remove(id)
        }
        message = nil
        rebuild()
        writeSummary()
    }

    // MARK: deletion

    public var marked: [Photo] { state.marked.compactMap { photos[$0] }.sorted { $0.asset.date > $1.asset.date } }

    public func unmark(_ id: String) {
        record([(id, .keep)], .confirm, done: "Kept 1")
    }

    /// One batch, one confirmation from Photos. Deleted photos stay in
    /// Recently Deleted for 30 days.
    public func deleteMarked() async {
        let ids = marked.map(\.id)
        guard !ids.isEmpty, !working.contains("delete") else { return }
        working.insert("delete")
        defer { working.remove("delete") }
        do {
            try await source.delete(ids)
            try? save { s in for id in ids { s.decisions[id] = nil } }
            for id in ids { photos[id] = nil }
            undoStack.removeAll()  // Photos owns undo now: Recently Deleted
            rebuild()
            message = "Deleted \(ids.count) photo\(ids.count == 1 ? "" : "s"). They stay in Recently Deleted in Photos for 30 days."
        } catch is DeleteCancelled {
            message = nil
        } catch {
            message = "Photos did not delete them: \(error.localizedDescription)"
        }
        writeSummary()
    }

    // MARK: best of

    public func visibleEvents(_ f: EventFilter) -> [Event] { events.filter { status($0).rawValue == f.rawValue } }
    public func status(_ e: Event) -> BestEvent.Status { state.best[e.id]?.status ?? .todo }
    public func name(_ e: Event) -> String { state.best[e.id]?.name ?? e.autoName }

    public func picked(_ e: Event) -> Set<String> {
        pickEdits[e.id] ?? Set(state.best[e.id]?.picked ?? e.suggested)
    }

    public func togglePick(_ e: Event, _ id: String) {
        var s = picked(e)
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        pickEdits[e.id] = s
    }

    public func export(_ e: Event) async {
        let ids = e.candidates.map(\.id).filter(picked(e).contains)
        guard !ids.isEmpty else { message = "Tick at least one photo to export, or skip the event."; return }
        await exportNamed(e, name: name(e), picked: ids)
    }

    private func exportNamed(_ e: Event, name: String, picked ids: [String]) async {
        working.insert(e.id)
        defer { working.remove(e.id) }
        do {
            let st = try await exporter.export(e, name: name, picked: ids, previous: state.best[e.id], source: source)
            try save { $0.best[e.id] = st }
            pickEdits[e.id] = nil
            try exporter.writeManifest(state: state, events: events)
            message = nil
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    public func rename(_ e: Event, to raw: String) async {
        let n = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !n.isEmpty, n != name(e) else { return }
        if status(e) == .exported, let p = state.best[e.id]?.picked {
            await exportNamed(e, name: n, picked: p)  // moves the folder
        } else {
            try? save { s in var b = s.best[e.id] ?? BestEvent(); b.name = n; s.best[e.id] = b }
        }
    }

    public func skipEvent(_ e: Event) {
        try? save { s in var b = s.best[e.id] ?? BestEvent(); b.status = .skipped; s.best[e.id] = b }
    }

    public func reopenEvent(_ e: Event) {
        try? save { s in var b = s.best[e.id] ?? BestEvent(); b.status = b.files.isEmpty ? .todo : .exported; s.best[e.id] = b }
    }

    /// Naming places sends each event's approximate location to Apple, so it
    /// is off until you turn it on.
    public func setNamePlaces(_ on: Bool) async {
        try? save { $0.namePlaces = on }
        if on { await namePlaces() }
        rebuild()
    }

    func namePlaces() async {
        let geocoder = CLGeocoder()
        for e in events where state.placeNames[e.id] == nil {
            guard let c = e.center else { continue }
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            guard let mark = try? await geocoder.reverseGeocodeLocation(loc).first,
                  let name = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea else { continue }
            try? save { $0.placeNames[e.id] = name }
        }
    }
}

extension AppModel {
    /// The real app: PhotoKit, state in Application Support, export to ~/Pictures/best-of.
    /// ATTIC_HOME and ATTIC_BEST override the folders; ATTIC_FIXTURE uses a folder library.
    public static func live() -> AppModel {
        let env = ProcessInfo.processInfo.environment
        let home = env["ATTIC_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Attic")
        let source: PhotoSource = env["ATTIC_FIXTURE"].map { FolderSource(dir: URL(fileURLWithPath: $0)) } ?? PhotoKitSource()
        return AppModel(source: source,
                        store: StateStore(url: home.appendingPathComponent("state.json")),
                        analyzer: Analyzer(cacheURL: home.appendingPathComponent("features.json")),
                        exporter: Exporter(root: Exporter.defaultRoot),
                        summaryURL: home.appendingPathComponent("last-run.json"))
    }
}
