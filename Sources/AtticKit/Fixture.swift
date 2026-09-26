import CoreGraphics
import Foundation
import ImageIO
import AtticCore
import SwiftUI
import UniformTypeIdentifiers

/// A synthetic library: generated shapes, no real photos. Used by the tests
/// and the snapshot renderer so no test ever needs a real library.
public enum Fixture {
    public static let t0 = Date(timeIntervalSince1970: 1_775_210_400) // 3 Apr 2026, 10:00 UTC

    struct Spec { let id: String; let scene: Int; let shift: Double; let at: TimeInterval; let w: Int; let h: Int
                  var blur = false; var fav = false; var lat: Double?; var lon: Double?; var screenshot = false }

    static var specs: [Spec] {
        let away = (43.70, 7.26), home = (48.86, 2.35)
        var s: [Spec] = []
        // Retakes: one scene, five tries a minute apart; #4 blurred.
        for i in 0..<5 {
            s.append(Spec(id: "RET\(i)/L0/001", scene: 1, shift: Double(i) * 0.012, at: Double(i) * 60,
                          w: 4032, h: 3024, blur: i == 3, lat: away.0, lon: away.1))
        }
        // A duplicate: the same picture re-saved small, 200 days later.
        s.append(Spec(id: "DUPA/L0/001", scene: 2, shift: 0, at: -86400 * 30, w: 4032, h: 3024, lat: home.0, lon: home.1))
        s.append(Spec(id: "DUPB/L0/001", scene: 2, shift: 0, at: 86400 * 170, w: 1600, h: 1200, lat: home.0, lon: home.1))
        // A trip day: three different scenes the next day, same region.
        for i in 0..<3 {
            s.append(Spec(id: "TRIP\(i)/L0/001", scene: 10 + i, shift: 0, at: 86400 + Double(i) * 1800,
                          w: 4032, h: 3024, fav: i == 2, lat: away.0 + 0.01, lon: away.1))
        }
        // Home days, spread out, plus a screenshot.
        for i in 0..<6 {
            s.append(Spec(id: "HOME\(i)/L0/001", scene: 20 + i, shift: 0, at: -86400 * Double(10 + i * 3),
                          w: 3024, h: 4032, lat: home.0, lon: home.1))
        }
        s.append(Spec(id: "SHOT/L0/001", scene: 30, shift: 0, at: 86400 + 60, w: 1179, h: 2556, screenshot: true))
        return s
    }

    /// Writes the library into `dir` and returns it.
    @discardableResult
    public static func make(at dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var assets: [Asset] = []
        for sp in specs {
            let img = draw(scene: sp.scene, shift: sp.shift, w: min(sp.w, 1200), h: scaledHeight(sp), blur: sp.blur)
            try write(img, to: dir.appendingPathComponent(FolderSource.file(for: sp.id)), lat: sp.lat, lon: sp.lon)
            assets.append(Asset(id: sp.id, date: t0.addingTimeInterval(sp.at), width: sp.w, height: sp.h,
                                favorite: sp.fav, screenshot: sp.screenshot, latitude: sp.lat, longitude: sp.lon))
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        try enc.encode(assets).write(to: dir.appendingPathComponent("library.json"))
        try enc.encode(features()).write(to: dir.appendingPathComponent("features.json"))
        return dir
    }

    /// Designed prints: retakes sit close on one circle, everything else is
    /// orthogonal (distance ~1.41). Labels make the trip a beach trip.
    static func features() -> [String: Features] {
        func onehot(_ k: Int) -> [Float] { var v = [Float](repeating: 0, count: 32); v[k] = 1; return v }
        var out: [String: Features] = [:]
        for (i, sp) in specs.enumerated() {
            var print: [Float]
            var hash = UInt64(i + 1) &* 0x9E3779B97F4A7C15
            var labels: [String: Double] = [:]
            var sharp = 180.0, aesthetic = 0.1, faces = 0, faceMin: Double? = nil
            switch sp.id.prefix(3) {
            case "RET":
                let a = Double(sp.id.dropFirst(3).prefix(1))! * 0.06
                print = [Float](repeating: 0, count: 32); print[0] = Float(cos(a)); print[1] = Float(sin(a))
                labels = ["beach": 0.8]; faces = 2; faceMin = sp.blur ? 0.2 : 0.5 + 0.05 * a
                if sp.blur { sharp = 20 }
            case "DUP": print = onehot(2); hash = 0xABCDEF
            case "TRI": print = onehot(3 + i % 5); labels = ["beach": 0.7, "ocean": 0.5]; aesthetic = 0.2 + 0.1 * Double(i % 3)
            default: print = onehot(10 + i % 20)
            }
            out[sp.id] = Features(print: print, dhash: hash, faces: faces, faceMin: faceMin, aesthetic: aesthetic,
                                  utility: sp.screenshot, sharpness: sharp, clipped: 0.01, labels: labels)
        }
        return out
    }

    static func scaledHeight(_ sp: Spec) -> Int { Int(Double(min(sp.w, 1200)) * Double(sp.h) / Double(sp.w)) }

    /// A deterministic "scene": sky gradient, horizon, a few shapes. `shift`
    /// nudges everything a little, like a retake from the same spot.
    static func draw(scene: Int, shift: Double, w: Int, h: Int, blur: Bool) -> CGImage {
        var rng = SplitMix(seed: UInt64(scene) &* 0x9E3779B97F4A7C15)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let top = CGColor(srgbRed: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: 1)
        let bottom = CGColor(srgbRed: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: 1)
        let grad = CGGradient(colorsSpace: nil, colors: [bottom, top] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        let dx = shift * Double(w), W = Double(w), H = Double(h)
        for _ in 0..<7 {
            ctx.setFillColor(CGColor(srgbRed: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: 1))
            let r = CGRect(x: rng.unit() * W * 0.8 + dx, y: rng.unit() * H * 0.7, width: W * (0.08 + rng.unit() * 0.25), height: H * (0.08 + rng.unit() * 0.25))
            if rng.unit() > 0.5 { ctx.fillEllipse(in: r) } else { ctx.fill(r) }
        }
        var img = ctx.makeImage()!
        if blur { img = boxBlur(img, radius: 9) }
        return img
    }

    static func boxBlur(_ img: CGImage, radius: Int) -> CGImage {
        // Downscale and back up: cheap, obvious blur.
        let small = CGContext(data: nil, width: img.width / radius, height: img.height / radius, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(img, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        let big = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        big.interpolationQuality = .high
        big.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return big.makeImage()!
    }

    /// JPEG with camera-like metadata, GPS included, so export stripping is tested for real.
    public static func write(_ img: CGImage, to url: URL, lat: Double?, lon: Double?) throws {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AtticError("cannot write \(url.path)")
        }
        var props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
        ]
        if let lat, let lon {
            props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: abs(lat), kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
                                                    kCGImagePropertyGPSLongitude: abs(lon), kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W"]
        }
        CGImageDestinationAddImage(d, img, props as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw AtticError("cannot finalize \(url.path)") }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
