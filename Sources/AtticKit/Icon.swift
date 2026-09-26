import AppKit
import SwiftUI

/// The app icon, drawn in code so there is no binary asset to keep in sync.
/// "The window": a round attic window, lit warm, two photos leaning inside, set in a teal wall.
/// Geometry is on a 100-unit grid (the design board's SVG), scaled to the
/// 1000 px icon body.
struct IconArt: View {
    static let u: CGFloat = 12.2  // px per grid unit: the 82-unit body is 1000 px
    let cream = Color(red: 0.957, green: 0.918, blue: 0.824)   // #f4ead2
    let wall = LinearGradient(colors: [Color(red: 0.247, green: 0.490, blue: 0.455), Color(red: 0.122, green: 0.290, blue: 0.275)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    let glass = RadialGradient(colors: [Color(red: 1, green: 0.965, blue: 0.847), Color(red: 0.953, green: 0.710, blue: 0.396)],
                               center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 30 * 1.4 * 12.2)

    var body: some View {
        let u = Self.u
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous).fill(wall).frame(width: 1000, height: 1000)
            // A faint shadow the window casts into the wall, so it sits in it.
            Circle().fill(Color.black.opacity(0.22)).frame(width: 64 * u, height: 64 * u).blur(radius: 18).offset(y: 14)
            Circle().fill(glass).frame(width: 60 * u, height: 60 * u)
            photo(inner: Color(red: 0.890, green: 0.420, blue: 0.353)).rotationEffect(.degrees(-10)).offset(x: -9.5 * u, y: -0.5 * u)
            photo(inner: Color(red: 0.310, green: 0.561, blue: 0.839)).rotationEffect(.degrees(8)).offset(x: 7.5 * u, y: -3.5 * u)
            // Mullions and frame over the photos, as in a real window.
            Rectangle().fill(cream).frame(width: 3.5 * u, height: 60 * u)
            Rectangle().fill(cream).frame(width: 60 * u, height: 3.5 * u)
            Circle().stroke(cream, lineWidth: 6 * u).frame(width: 60 * u, height: 60 * u)
            // A soft glint on the glass.
            Ellipse().fill(Color.white.opacity(0.35)).frame(width: 5 * u, height: 11 * u)
                .rotationEffect(.degrees(35)).offset(x: -15 * u, y: -14 * u)
        }
        .scaleEffect(0.824)  // macOS icon grid: 824 pt body inside the 1024 canvas
        .frame(width: 1024, height: 1024)
    }

    /// A print: white border, coloured picture set high, like an instant photo.
    func photo(inner: Color) -> some View {
        let u = Self.u
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1.5 * u).fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            Rectangle().fill(inner).frame(width: 11 * u, height: 11 * u).padding(.top, 2 * u)
        }
        .frame(width: 15 * u, height: 19 * u)
    }
}

public enum Icon {
    @MainActor
    public static func png(to url: URL) throws {
        let r = ImageRenderer(content: IconArt())
        r.scale = 1
        guard let tiff = r.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw AtticError("icon did not render")
        }
        try png.write(to: url)
    }
}
