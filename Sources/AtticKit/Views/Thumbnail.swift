import AppKit
import SwiftUI

/// Thumbnails from the photo source, cached in memory. Local only: a photo
/// that is only in iCloud shows a placeholder rather than downloading.
@MainActor
public final class ThumbnailStore {
    private let cache = NSCache<NSString, NSImage>()
    let source: PhotoSource
    public init(source: PhotoSource) { self.source = source; cache.countLimit = 800 }

    public func cached(_ id: String, _ px: Int) -> NSImage? { cache.object(forKey: "\(px):\(id)" as NSString) }

    public func load(_ id: String, _ px: Int) async -> NSImage? {
        if let hit = cached(id, px) { return hit }
        guard let cg = await source.thumbnail(id, maxPixels: px, allowNetwork: false) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: "\(px):\(id)" as NSString)
        return img
    }
}

struct Thumb: View {
    let id: String
    var px = 400
    /// Width / height of the tile. The photo fills it and is cropped to it.
    var aspect: CGFloat = 3 / 4
    @Environment(ThumbnailStoreBox.self) private var store
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.line)
            .overlay {
                if let img = image ?? store.store.cached(id, px) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: "icloud").foregroundStyle(Theme.muted)
                        .help("Only in iCloud. Open it once in Photos to bring it to this Mac.")
                }
            }
            .clipped()
            .task(id: id) {
                if image == nil { image = await store.store.load(id, px); failed = image == nil }
            }
    }
}

/// A single photo shown whole, for the zoom sheet.
struct Zoomed: View {
    let id: String
    @Environment(ThumbnailStoreBox.self) private var store
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.bg
            if let image { Image(nsImage: image).resizable().scaledToFit() } else { ProgressView() }
        }
        .task(id: id) { image = await store.store.load(id, 1600) }
    }
}

/// Environment carrier (NSCache is not Observable).
@Observable @MainActor
public final class ThumbnailStoreBox {
    public let store: ThumbnailStore
    public init(_ store: ThumbnailStore) { self.store = store }
}
