import Foundation

/// One photo in the library, as PhotoKit describes it. `id` is the
/// PHAsset localIdentifier ("UUID/L0/001").
public struct Asset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var width: Int
    public var height: Int
    public var favorite: Bool
    public var edited: Bool
    public var screenshot: Bool
    /// Kept on this Mac only, for grouping events. Never exported.
    public var latitude: Double?
    public var longitude: Double?

    public init(id: String, date: Date, width: Int, height: Int, favorite: Bool = false,
                edited: Bool = false, screenshot: Bool = false,
                latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id; self.date = date; self.width = width; self.height = height
        self.favorite = favorite; self.edited = edited; self.screenshot = screenshot
        self.latitude = latitude; self.longitude = longitude
    }

    public var pixels: Double { Double(max(width, 1)) * Double(max(height, 1)) }
    public var hasLocation: Bool { latitude != nil && longitude != nil }
}

/// What on-device analysis found in one photo. A missing value means
/// "not measured", never zero (INVARIANTS: blanks are never zeros).
public struct Features: Codable, Hashable, Sendable {
    public static let version = 1

    /// Vision feature print, normalised to unit length.
    public var print: [Float]
    /// 64-bit difference hash of a 9x8 greyscale thumbnail.
    public var dhash: UInt64
    public var faces: Int
    /// Worst face in the frame (blinks, blur, turned heads decide a group shot).
    public var faceMin: Double?
    public var faceMean: Double?
    /// Vision's aesthetics score, roughly -1...1.
    public var aesthetic: Double?
    /// Receipts, documents, screenshots: never "best of".
    public var utility: Bool
    public var sharpness: Double
    /// Share of pixels crushed to black or blown to white.
    public var clipped: Double
    /// Activity labels (see Activities) with Vision's confidence.
    public var labels: [String: Double]

    public init(print: [Float], dhash: UInt64, faces: Int = 0, faceMin: Double? = nil,
                faceMean: Double? = nil, aesthetic: Double? = nil, utility: Bool = false,
                sharpness: Double = 0, clipped: Double = 0, labels: [String: Double] = [:]) {
        self.print = Similarity.normalised(print); self.dhash = dhash; self.faces = faces
        self.faceMin = faceMin; self.faceMean = faceMean; self.aesthetic = aesthetic
        self.utility = utility; self.sharpness = sharpness; self.clipped = clipped; self.labels = labels
    }
}

public struct Photo: Hashable, Sendable, Identifiable {
    public let asset: Asset
    public let features: Features
    public var id: String { asset.id }
    public init(asset: Asset, features: Features) { self.asset = asset; self.features = features }
}
