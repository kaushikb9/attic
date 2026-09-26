import AppKit
import CoreGraphics
import Foundation
import ImageIO
import AtticCore
import Photos

public enum Access: Sendable { case granted, denied }

public struct DeleteCancelled: Error {}

/// Where photos come from. PhotoKit in the app; a folder of images in tests
/// and snapshots, so no test ever touches the real library.
public protocol PhotoSource: AnyObject, Sendable {
    func requestAccess() async -> Access
    func loadAssets() async -> [Asset]
    /// Only what is already on this Mac unless `allowNetwork`.
    func thumbnail(_ id: String, maxPixels: Int, allowNetwork: Bool) async -> CGImage?
    /// Full-size data for export: your edited version if there is one. May download from iCloud.
    func original(_ id: String) async throws -> Data
    /// Moves photos to Recently Deleted. PhotoKit asks you to confirm first.
    func delete(_ ids: [String]) async throws
    func modified(_ id: String) -> Date?
}

// MARK: - PhotoKit

public final class PhotoKitSource: PhotoSource, @unchecked Sendable {
    private var assets: [String: PHAsset] = [:]
    private let lock = NSLock()

    public init() {}

    public func requestAccess() async -> Access {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited ? .granted : .denied
    }

    public func loadAssets() async -> [Asset] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetch = PHAsset.fetchAssets(with: .image, options: opts)
        var out: [Asset] = []
        var map: [String: PHAsset] = [:]
        fetch.enumerateObjects { a, _, _ in
            map[a.localIdentifier] = a
            out.append(Asset(id: a.localIdentifier, date: a.creationDate ?? .distantPast,
                             width: a.pixelWidth, height: a.pixelHeight, favorite: a.isFavorite,
                             edited: a.hasAdjustments,
                             screenshot: a.mediaSubtypes.contains(.photoScreenshot),
                             latitude: a.location?.coordinate.latitude,
                             longitude: a.location?.coordinate.longitude))
        }
        lock.withLock { assets = map }
        return out
    }

    private func asset(_ id: String) -> PHAsset? {
        if let a = lock.withLock({ assets[id] }) { return a }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    public func modified(_ id: String) -> Date? { asset(id)?.modificationDate }

    public func thumbnail(_ id: String, maxPixels: Int, allowNetwork: Bool) async -> CGImage? {
        guard let a = asset(id) else { return nil }
        if let img = await request(a, maxPixels, .highQualityFormat, allowNetwork) { return img }
        // Photos returns nothing for high quality when only a smaller preview is
        // on this Mac (114 of 793 photos, 2026-09-26). Take the preview it has:
        // still no download, and plenty for Vision.
        return allowNetwork ? nil : await request(a, maxPixels, .fastFormat, false)
    }

    private func request(_ a: PHAsset, _ maxPixels: Int, _ mode: PHImageRequestOptionsDeliveryMode,
                         _ allowNetwork: Bool) async -> CGImage? {
        let o = PHImageRequestOptions()
        o.deliveryMode = mode
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = allowNetwork
        o.isSynchronous = false
        let size = CGSize(width: maxPixels, height: maxPixels)
        return await withCheckedContinuation { (c: CheckedContinuation<CGImage?, Never>) in
            var done = false
            PHImageManager.default().requestImage(for: a, targetSize: size, contentMode: .aspectFit, options: o) { img, info in
                // High quality may call back with a degraded image first; wait for the real one.
                if mode == .highQualityFormat, (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard !done else { return }
                done = true
                c.resume(returning: img?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    public func original(_ id: String) async throws -> Data {
        guard let a = asset(id) else { throw AtticError("That photo is no longer in Photos. Rescan and try again.") }
        let o = PHImageRequestOptions()
        o.version = .current
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { c in
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { data, _, _, info in
                if let data { c.resume(returning: data); return }
                let err = info?[PHImageErrorKey] as? Error
                c.resume(throwing: AtticError("Photos could not provide the original" +
                                              (err.map { ": \($0.localizedDescription)" } ?? ". Check your internet connection for iCloud photos.")))
            }
        }
    }

    public func delete(_ ids: [String]) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetch)
            }
        } catch let e as NSError where e.domain == PHPhotosErrorDomain && e.code == PHPhotosError.userCancelled.rawValue {
            throw DeleteCancelled()
        } catch let e as NSError where e.code == 3072 {  // NSUserCancelledError
            throw DeleteCancelled()
        }
    }
}

// MARK: - Folder (tests, snapshots)

/// A folder holding `library.json` ([Asset]) and one `<file-safe id>.jpg`
/// per asset. Deleting moves ids into `deleted.json`.
public final class FolderSource: PhotoSource, @unchecked Sendable {
    public let dir: URL
    public var access: Access = .granted
    public private(set) var deleteCalls: [[String]] = []
    public var cancelNextDelete = false

    public init(dir: URL) { self.dir = dir }

    public static func file(for id: String) -> String { id.replacingOccurrences(of: "/", with: "_") + ".jpg" }

    var deletedURL: URL { dir.appendingPathComponent("deleted.json") }
    public var deleted: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: deletedURL))) ?? []
    }

    public func requestAccess() async -> Access { access }

    public func loadAssets() async -> [Asset] {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let all = (try? d.decode([Asset].self, from: Data(contentsOf: dir.appendingPathComponent("library.json")))) ?? []
        let gone = deleted
        return all.filter { !gone.contains($0.id) }
    }

    public func modified(_ id: String) -> Date? { nil }

    /// Designed features from `features.json`, so fixture grouping is exact
    /// and does not depend on how Vision reads synthetic shapes.
    public lazy var precomputed: [String: Features] = {
        (try? JSONDecoder().decode([String: Features].self, from: Data(contentsOf: dir.appendingPathComponent("features.json")))) ?? [:]
    }()

    public func thumbnail(_ id: String, maxPixels: Int, allowNetwork: Bool) async -> CGImage? {
        let url = dir.appendingPathComponent(Self.file(for: id))
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    public func original(_ id: String) async throws -> Data {
        try Data(contentsOf: dir.appendingPathComponent(Self.file(for: id)))
    }

    public func delete(_ ids: [String]) async throws {
        if cancelNextDelete { cancelNextDelete = false; throw DeleteCancelled() }
        deleteCalls.append(ids)
        try JSONEncoder().encode(deleted.union(ids)).write(to: deletedURL)
    }
}

public struct AtticError: Error, LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { message }
}
