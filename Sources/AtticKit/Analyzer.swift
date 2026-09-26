import CoreGraphics
import Foundation
import AtticCore
import Vision

/// On-device analysis with Apple Vision. Nothing leaves the Mac.
/// Results are cached per photo (keyed by id and modification date), so a
/// rescan only analyses what is new or edited.
public final class Analyzer: @unchecked Sendable {
    struct Entry: Codable { var modified: Date?; var features: Features }
    struct CacheFile: Codable { var version: Int; var entries: [String: Entry] }

    public static let thumbPixels = 512
    let cacheURL: URL?
    private var cache: [String: Entry] = [:]
    private let lock = NSLock()

    public init(cacheURL: URL?) {
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let file = try? JSONDecoder.atticKit.decode(CacheFile.self, from: data),
           file.version == Features.version {
            cache = file.entries
        }
    }

    public struct Result: Sendable {
        public var photos: [Photo]
        /// No thumbnail on this Mac (iCloud-only). Not downloaded on purpose.
        public var unavailable: Int
    }

    public func analyze(_ assets: [Asset], source: PhotoSource,
                        progress: @escaping @Sendable (Int, Int) -> Void) async -> Result {
        let total = assets.count
        var photos: [Photo] = []
        var unavailable = 0
        var done = 0
        var fresh = 0
        await withTaskGroup(of: (Asset, Features?).self) { group in
            var it = assets.makeIterator()
            func next() -> Bool {
                guard let a = it.next() else { return false }
                let mod = source.modified(a.id)
                if let pre = (source as? FolderSource)?.precomputed[a.id] {
                    group.addTask { (a, pre) }
                } else if let hit = lock.withLock({ cache[a.id] }), hit.modified == mod {
                    group.addTask { (a, hit.features) }
                } else {
                    group.addTask {
                        guard let img = await source.thumbnail(a.id, maxPixels: Self.thumbPixels, allowNetwork: false),
                              let f = try? Self.features(of: img) else { return (a, nil) }
                        return (a, f)
                    }
                }
                return true
            }
            for _ in 0..<6 { if !next() { break } }
            while let (a, f) = await group.next() {
                done += 1
                if let f {
                    photos.append(Photo(asset: a, features: f))
                    let mod = source.modified(a.id)
                    lock.withLock {
                        if cache[a.id]?.modified != mod || cache[a.id] == nil { fresh += 1 }
                        cache[a.id] = Entry(modified: mod, features: f)
                    }
                } else {
                    unavailable += 1
                }
                if done % 25 == 0 || done == total { progress(done, total) }
                if fresh > 0 && fresh % 200 == 0 { save() }
                _ = next()
            }
        }
        save()
        return Result(photos: photos, unavailable: unavailable)
    }

    public func save() {
        guard let cacheURL else { return }
        let entries = lock.withLock { cache }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.atticKit.encode(CacheFile(version: Features.version, entries: entries)).write(to: cacheURL, options: .atomic)
    }

    // MARK: per-image

    public static func features(of image: CGImage) throws -> Features {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let fp = VNGenerateImageFeaturePrintRequest()
        let faces = VNDetectFaceCaptureQualityRequest()
        let aes = VNCalculateImageAestheticsScoresRequest()
        let cls = VNClassifyImageRequest()
        try handler.perform([fp, faces, aes, cls])

        guard let obs = fp.results?.first else { throw AtticError("Vision returned no feature print") }
        let vec: [Float] = obs.data.withUnsafeBytes { raw in
            obs.elementType == .double
                ? raw.bindMemory(to: Double.self).map { Float($0) }
                : Array(raw.bindMemory(to: Float.self))
        }
        let qs = (faces.results ?? []).compactMap { $0.faceCaptureQuality.map(Double.init) }
        let a = aes.results?.first
        var labels: [String: Double] = [:]
        for c in cls.results ?? [] where c.confidence >= 0.2 && Activity.allLabels.contains(c.identifier) {
            labels[c.identifier] = (Double(c.confidence) * 1000).rounded() / 1000
        }
        let px = pixelStats(image)
        return Features(print: vec, dhash: dhash(image), faces: qs.count,
                        faceMin: qs.min(), faceMean: qs.isEmpty ? nil : qs.reduce(0, +) / Double(qs.count),
                        aesthetic: a.map { Double($0.overallScore) }, utility: a?.isUtility ?? false,
                        sharpness: px.sharpness, clipped: px.clipped, labels: labels)
    }

    static func grey(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: width * height)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? buf : nil
    }

    /// Laplacian variance (sharpness) and the share of crushed or blown pixels.
    static func pixelStats(_ image: CGImage) -> (sharpness: Double, clipped: Double) {
        let scale = min(1, 512 / Double(max(image.width, image.height)))
        let w = max(3, Int(Double(image.width) * scale)), h = max(3, Int(Double(image.height) * scale))
        guard let g = grey(image, width: w, height: h) else { return (0, 0) }
        let clipped = g.reduce(0) { $0 + ($1 < 6 || $1 > 249 ? 1 : 0) }
        var sum = 0.0, sq = 0.0, n = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let lap = Double(g[i - w]) + Double(g[i + w]) + Double(g[i - 1]) + Double(g[i + 1]) - 4 * Double(g[i])
                sum += lap; sq += lap * lap; n += 1
            }
        }
        let mean = sum / n
        return ((sq / n - mean * mean).rounded(), Double(clipped) / Double(w * h))
    }

    /// Difference hash: 9x8 greyscale, one bit per left/right comparison.
    static func dhash(_ image: CGImage) -> UInt64 {
        guard let g = grey(image, width: 9, height: 8) else { return 0 }
        var h: UInt64 = 0
        for y in 0..<8 { for x in 0..<8 { h = (h << 1) | (g[y * 9 + x] > g[y * 9 + x + 1] ? 1 : 0) } }
        return h
    }
}

extension JSONEncoder {
    static var atticKit: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

extension JSONDecoder {
    static var atticKit: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
