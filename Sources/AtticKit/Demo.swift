import CoreGraphics
import Foundation
import AtticCore

/// A demo library for README screenshots: illustrated scenes drawn in code
/// (no real or downloaded photos), with designed analysis so every section
/// has something to show. `Attic --make-demo <dir>`, then run with ATTIC_FIXTURE.
public enum Demo {
    enum Kind { case beach, mountain, city, sunset, food, park }

    struct Shot {
        let id: String; let kind: Kind; let seed: Int; let day: Double; let minute: Double
        var shift = 0.0; var blur = false; var people = 0; var w = 4032; var h = 3024
        var fav = false; var lat: Double? = nil; var lon: Double? = nil
        var faceMin: Double? = nil; var aesthetic = 0.1
    }

    static let t0 = Date(timeIntervalSince1970: 1_775_210_400) // 3 Apr 2026
    static let home = (48.86, 2.35), coast = (43.70, 7.26), alps = (45.92, 6.87)

    static var shots: [Shot] {
        var s: [Shot] = []
        // Retakes: five tries at a photo of two friends on the beach. #2 blinked, #3 is blurred.
        for i in 0..<5 {
            s.append(Shot(id: "RT\(i)", kind: .beach, seed: 1, day: 0, minute: Double(i), shift: Double(i) * 0.015,
                          blur: i == 2, people: 2, lat: coast.0, lon: coast.1,
                          faceMin: i == 1 ? 0.15 : i == 2 ? 0.3 : 0.55 + 0.05 * Double(i), aesthetic: 0.2 + 0.05 * Double(i)))
        }
        // Retakes: three shots of the same lunch.
        for i in 0..<3 {
            s.append(Shot(id: "FD\(i)", kind: .food, seed: 2, day: 1, minute: 60 * 5 + Double(i), shift: Double(i) * 0.01,
                          w: 3024, h: 3024, lat: coast.0, lon: coast.1, aesthetic: 0.1 + 0.1 * Double(i)))
        }
        // A beach trip: different scenes over three days.
        for (i, seed) in [11, 12, 13, 14, 15].enumerated() {
            s.append(Shot(id: "BT\(i)", kind: i == 3 ? .sunset : .beach, seed: seed, day: Double(i / 2), minute: 180 + Double(i) * 97,
                          people: i % 2, fav: i == 3, lat: coast.0 + 0.01 * Double(i), lon: coast.1, aesthetic: 0.15 * Double(i)))
        }
        // A mountain weekend in January.
        for (i, seed) in [21, 22, 23, 24].enumerated() {
            s.append(Shot(id: "MT\(i)", kind: .mountain, seed: seed, day: -80 + Double(i / 2), minute: 120 + Double(i) * 110,
                          people: i == 1 ? 1 : 0, lat: alps.0, lon: alps.1, aesthetic: 0.1 * Double(i)))
        }
        // A city evening at home.
        for (i, seed) in [31, 32, 33].enumerated() {
            s.append(Shot(id: "CT\(i)", kind: .city, seed: seed, day: -30, minute: 1140 + Double(i) * 20,
                          lat: home.0, lon: home.1, aesthetic: 0.1 * Double(i)))
        }
        // A duplicate: the same sunset, re-saved small from a messaging app a year later.
        s.append(Shot(id: "DUP0", kind: .sunset, seed: 41, day: -200, minute: 1200, lat: home.0, lon: home.1))
        s.append(Shot(id: "DUP1", kind: .sunset, seed: 41, day: 165, minute: 600, w: 1280, h: 960, lat: home.0, lon: home.1))
        // Everyday photos at home, one every few days: they make home home.
        for i in 0..<14 {
            s.append(Shot(id: "PK\(i)", kind: .park, seed: 50 + i, day: -40 - Double(i * 7), minute: 600, lat: home.0, lon: home.1))
        }
        return s
    }

    @discardableResult
    public static func make(at dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var assets: [Asset] = [], feats: [String: Features] = [:]
        for (n, sp) in shots.enumerated() {
            let id = "\(sp.id)/L0/001"
            let w = 1200, h = Int(1200.0 * Double(sp.h) / Double(sp.w))
            var img = draw(sp, w: w, h: h)
            if sp.blur { img = Fixture.boxBlur(img, radius: 8) }
            try Fixture.write(img, to: dir.appendingPathComponent(FolderSource.file(for: id)), lat: sp.lat, lon: sp.lon)
            assets.append(Asset(id: id, date: t0.addingTimeInterval(sp.day * 86400 + sp.minute * 60), width: sp.w, height: sp.h,
                                favorite: sp.fav, latitude: sp.lat, longitude: sp.lon))
            feats[id] = features(sp, n)
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        try enc.encode(assets).write(to: dir.appendingPathComponent("library.json"))
        try enc.encode(feats).write(to: dir.appendingPathComponent("features.json"))
        return dir
    }

    /// Designed analysis: retakes sit close on a circle, everything else apart.
    static func features(_ sp: Shot, _ n: Int) -> Features {
        var v = [Float](repeating: 0, count: 64)
        switch sp.id.prefix(2) {
        case "RT": v[0] = Float(cos(sp.shift * 4)); v[1] = Float(sin(sp.shift * 4))
        case "FD": v[2] = Float(cos(sp.shift * 5)); v[3] = Float(sin(sp.shift * 5))
        case "DU": v[4] = 1
        default: v[8 + n % 50] = 1
        }
        let labels: [String: Double] = switch sp.kind {
        case .beach, .sunset: ["beach": 0.8, "ocean": 0.6]
        case .mountain: ["mountain": 0.8, "hiking": 0.5]
        case .city: ["cityscape": 0.7]
        case .food: ["food": 0.9]
        case .park: ["garden": 0.4]
        }
        return Features(print: v, dhash: sp.id.hasPrefix("DUP") ? 0xC0FFEE : UInt64(n + 1) &* 0x9E3779B97F4A7C15,
                        faces: sp.people, faceMin: sp.people > 0 ? (sp.faceMin ?? 0.6) : nil, aesthetic: sp.aesthetic,
                        sharpness: sp.blur ? 15 : 160, clipped: 0.01, labels: labels)
    }

    // MARK: drawing (CoreGraphics, origin bottom-left)

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    static func draw(_ sp: Shot, w: Int, h: Int) -> CGImage {
        var rng = SplitMix(seed: UInt64(sp.seed) &* 0x9E3779B97F4A7C15)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let W = Double(w), H = Double(h), dx = sp.shift * W
        func gradient(_ top: CGColor, _ bottom: CGColor, from y0: Double, to y1: Double) {
            let g = CGGradient(colorsSpace: nil, colors: [bottom, top] as CFArray, locations: [0, 1])!
            ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: y0, width: W, height: y1 - y0))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
            ctx.restoreGState()
        }
        func person(_ x: Double, _ y: Double, _ s: Double, _ c: CGColor) {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: x - s * 0.18, y: y + s * 0.62, width: s * 0.36, height: s * 0.36))
            let body = CGMutablePath()
            body.move(to: CGPoint(x: x - s * 0.3, y: y)); body.addLine(to: CGPoint(x: x + s * 0.3, y: y))
            body.addQuadCurve(to: CGPoint(x: x - s * 0.3, y: y), control: CGPoint(x: x, y: y + s * 1.25))
            ctx.addPath(body); ctx.fillPath()
        }
        switch sp.kind {
        case .beach:
            gradient(rgb(0.36, 0.66, 0.93), rgb(0.78, 0.9, 0.98), from: H * 0.45, to: H)
            gradient(rgb(0.1, 0.45, 0.62), rgb(0.2, 0.62, 0.72), from: H * 0.3, to: H * 0.45)
            gradient(rgb(0.93, 0.83, 0.62), rgb(0.97, 0.9, 0.74), from: 0, to: H * 0.3)
            ctx.setFillColor(rgb(1, 0.95, 0.7)); ctx.fillEllipse(in: CGRect(x: W * (0.7 + rng.unit() * 0.15) + dx, y: H * 0.72, width: W * 0.09, height: W * 0.09))
            ctx.setFillColor(rgb(1, 1, 1).copy(alpha: 0.85)!)
            for _ in 0..<3 { ctx.fillEllipse(in: CGRect(x: rng.unit() * W * 0.8 + dx, y: H * (0.78 + rng.unit() * 0.12), width: W * 0.14, height: H * 0.05)) }
            ctx.setFillColor(rgb(0.45, 0.3, 0.18)); ctx.fill(CGRect(x: W * 0.12 + dx, y: H * 0.18, width: W * 0.018, height: H * 0.42))
            ctx.setFillColor(rgb(0.2, 0.55, 0.3))
            for a in stride(from: -2.4, through: -0.6, by: 0.45) {
                ctx.fillEllipse(in: CGRect(x: W * 0.129 + dx + cos(a + .pi) * W * 0.05 - W * 0.05, y: H * 0.58 + sin(a + .pi) * H * 0.02, width: W * 0.1, height: H * 0.035))
            }
            for p in 0..<sp.people { person(W * (0.45 + 0.13 * Double(p)) + dx, H * 0.12, H * 0.34, p == 0 ? rgb(0.85, 0.35, 0.3) : rgb(0.25, 0.4, 0.7)) }
        case .sunset:
            gradient(rgb(0.35, 0.25, 0.55), rgb(1, 0.6, 0.35), from: H * 0.4, to: H)
            ctx.setFillColor(rgb(1, 0.85, 0.5)); ctx.fillEllipse(in: CGRect(x: W * 0.42, y: H * 0.34, width: W * 0.16, height: W * 0.16))
            gradient(rgb(0.25, 0.2, 0.4), rgb(0.12, 0.12, 0.28), from: 0, to: H * 0.42)
            ctx.setFillColor(rgb(1, 0.75, 0.45).copy(alpha: 0.6)!)
            for i in 0..<5 { ctx.fill(CGRect(x: W * (0.4 + 0.01 * Double(i)), y: H * (0.36 - 0.05 * Double(i)), width: W * (0.2 - 0.02 * Double(i)), height: H * 0.012)) }
        case .mountain:
            gradient(rgb(0.45, 0.68, 0.92), rgb(0.85, 0.92, 0.98), from: 0, to: H)
            for (layer, col) in [(0.0, rgb(0.55, 0.62, 0.75)), (1.0, rgb(0.35, 0.45, 0.55)), (2.0, rgb(0.22, 0.38, 0.3))] {
                let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: 0))
                var x = 0.0
                while x <= W { p.addLine(to: CGPoint(x: x, y: H * (0.35 + 0.12 * (2 - layer) / 2) + rng.unit() * H * (0.28 - 0.07 * layer))); x += W / 5 }
                p.addLine(to: CGPoint(x: W, y: 0)); p.closeSubpath()
                ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath()
            }
            ctx.setFillColor(rgb(0.97, 0.98, 1)); ctx.fillEllipse(in: CGRect(x: W * 0.3, y: H * 0.62, width: W * 0.08, height: H * 0.04))
            if sp.people > 0 { person(W * 0.62, H * 0.08, H * 0.3, rgb(0.9, 0.5, 0.15)) }
        case .city:
            gradient(rgb(0.12, 0.14, 0.35), rgb(0.95, 0.55, 0.45), from: 0, to: H)
            for i in 0..<9 {
                let bw = W * (0.07 + rng.unit() * 0.06), bh = H * (0.25 + rng.unit() * 0.45), x = W * Double(i) / 9
                ctx.setFillColor(rgb(0.1, 0.1, 0.2)); ctx.fill(CGRect(x: x, y: 0, width: bw, height: bh))
                ctx.setFillColor(rgb(1, 0.85, 0.45))
                for _ in 0..<Int(bh / H * 18) { ctx.fill(CGRect(x: x + rng.unit() * (bw - 10), y: rng.unit() * (bh - 12), width: 8, height: 10)) }
            }
        case .food:
            ctx.setFillColor(rgb(0.55, 0.38, 0.25)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(rgb(0.97, 0.96, 0.94)); ctx.fillEllipse(in: CGRect(x: W * 0.2 + dx, y: H * 0.12, width: W * 0.6, height: W * 0.6))
            for (c, x, y, r) in [(rgb(0.9, 0.3, 0.2), 0.42, 0.45, 0.12), (rgb(0.3, 0.65, 0.3), 0.55, 0.35, 0.1), (rgb(0.98, 0.8, 0.3), 0.36, 0.3, 0.08)] {
                ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: W * x + dx, y: H * y, width: W * r, height: W * r))
            }
        case .park:
            gradient(rgb(0.55, 0.78, 0.95), rgb(0.85, 0.93, 0.98), from: H * 0.35, to: H)
            gradient(rgb(0.35, 0.65, 0.3), rgb(0.25, 0.5, 0.22), from: 0, to: H * 0.35)
            for _ in 0..<4 {
                let x = rng.unit() * W * 0.85
                ctx.setFillColor(rgb(0.4, 0.28, 0.18)); ctx.fill(CGRect(x: x + W * 0.035, y: H * 0.25, width: W * 0.02, height: H * 0.18))
                ctx.setFillColor(rgb(0.2, 0.5 + rng.unit() * 0.2, 0.25)); ctx.fillEllipse(in: CGRect(x: x, y: H * 0.38, width: W * 0.09, height: H * 0.2))
            }
        }
        return ctx.makeImage()!
    }
}
