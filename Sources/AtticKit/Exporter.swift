import CoreGraphics
import Foundation
import ImageIO
import AtticCore
import UniformTypeIdentifiers

/// Writes approved photos to the best-of folder, the only folder other agents
/// are given. Each file: at most 2400 px on the long edge, upright, and its
/// metadata is the capture time and the original GPS location. No camera, lens or serial numbers.
/// `manifest.json` names events and places; coordinates live in the files.
public struct Exporter: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        if let o = ProcessInfo.processInfo.environment["ATTIC_BEST"] { return URL(fileURLWithPath: o) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/best-of")
    }

    static let exifDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    /// Re-encode `data` as a clean JPEG at `url`.
    public func finalize(_ data: Data, taken: Date, to url: URL) throws {
        let url = try ExportNaming.inside(root, url)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AtticError("Could not read that photo's image data")
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: ExportNaming.maxEdge,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AtticError("Could not re-encode that photo")
        }
        var props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.88,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: Self.exifDate.string(from: taken)],
        ]
        // Keep where it was taken; drop everything else the camera wrote.
        if let original = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let gps = original[kCGImagePropertyGPSDictionary] {
            props[kCGImagePropertyGPSDictionary] = gps
        }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw AtticError("Could not write \(url.lastPathComponent)") }
    }

    /// Make the event's folder hold exactly `picked`. Returns the new state.
    public func export(_ event: Event, name: String, picked: [String], previous: BestEvent?,
                       source: PhotoSource) async throws -> BestEvent {
        let fm = FileManager.default
        let folder = try ExportNaming.inside(root, root.appendingPathComponent(ExportNaming.folder(start: event.start, name: name)))
        var st = previous ?? BestEvent()
        if let old = st.folder.map({ root.appendingPathComponent($0) }), old.path != folder.path,
           fm.fileExists(atPath: old.path) {
            _ = try ExportNaming.inside(root, old)
            try fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: old, to: folder)  // renamed event
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dates = Dictionary(uniqueKeysWithValues: event.candidates.map { ($0.id, $0.asset.date) })
        for (id, file) in st.files where !picked.contains(id) {
            let f = try ExportNaming.inside(root, folder.appendingPathComponent(file))
            try? fm.removeItem(at: f)  // unticked since the last export; only our own copy
            st.files[id] = nil
        }
        for id in picked {
            if let f = st.files[id], fm.fileExists(atPath: folder.appendingPathComponent(f).path) { continue }
            let taken = dates[id] ?? Date()
            let file = ExportNaming.file(date: taken, id: id)
            try finalize(try await source.original(id), taken: taken, to: folder.appendingPathComponent(file))
            st.files[id] = file
        }
        st.name = name
        st.picked = picked
        st.folder = folder.lastPathComponent
        st.status = .exported
        return st
    }

    struct Manifest: Codable {
        struct Item: Codable { let file: String; let photos_id: String; let date: Date? }
        struct Ev: Codable { let id: String; let name: String; let place: String?; let start: Date?; let end: Date?; let folder: String; let photos: [Item] }
        let generated: Date
        let events: [Ev]
    }

    public func writeManifest(state: AtticState, events: [Event]) throws {
        let byId = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        let evs = state.best.sorted { $0.key < $1.key }.compactMap { id, b -> Manifest.Ev? in
            guard b.status == .exported, let folder = b.folder else { return nil }
            let e = byId[id]
            let dates = Dictionary(uniqueKeysWithValues: (e?.candidates ?? []).map { ($0.id, $0.asset.date) })
            let place = state.namePlaces ? state.placeNames[id] : nil
            return Manifest.Ev(id: id, name: b.name ?? e?.autoName ?? id, place: place ?? e?.activity?.name,
                               start: e?.start, end: e?.end, folder: folder,
                               photos: b.files.sorted { $0.value < $1.value }.map {
                                   Manifest.Item(file: "\(folder)/\($0.value)", photos_id: $0.key, date: dates[$0.key])
                               })
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try ExportNaming.inside(root, root.appendingPathComponent("manifest.json"))
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        try enc.encode(Manifest(generated: Date(), events: evs)).write(to: url, options: .atomic)
    }
}
