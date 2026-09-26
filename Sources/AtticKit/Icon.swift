import AppKit
import SwiftUI

/// The app icon, drawn in code so there is no binary asset to keep in sync.
/// A round attic window, lit warm, two photos leaning inside, set in a teal
/// wall. Tuned for the Dock: one bold shape, big prints, no mullions or thin
/// lines, strong colours (the first version read as a pale disc at 55 pt).
/// Geometry is on a 100-unit grid, scaled to the 1000 px icon body.
struct IconArt: View {
    static let u: CGFloat = 12.2  // px per grid unit: the 82-unit body is 1000 px
    let cream = Color(red: 0.957, green: 0.918, blue: 0.824)
    let wall = LinearGradient(colors: [Color(red: 0.13, green: 0.43, blue: 0.40), Color(red: 0.04, green: 0.20, blue: 0.19)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    let glass = RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.66, blue: 0.22)],
                               center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 30 * 1.4 * 12.2)
    let red = Color(red: 0.91, green: 0.31, blue: 0.23)
    let blue = Color(red: 0.18, green: 0.49, blue: 0.88)

    var body: some View {
        let u = Self.u
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous).fill(wall).frame(width: 1000, height: 1000)
            Circle().fill(glass).frame(width: 70 * u, height: 70 * u)
            ZStack {
                photo(red).rotationEffect(.degrees(-12)).offset(x: -13 * u, y: 3 * u)
                photo(blue).rotationEffect(.degrees(10)).offset(x: 12 * u, y: -3 * u)
            }
            .frame(width: 70 * u, height: 70 * u).clipShape(Circle())
            Circle().stroke(cream, lineWidth: 5 * u).frame(width: 70 * u, height: 70 * u)
        }
        .scaleEffect(0.824)  // macOS icon grid: 824 pt body inside the 1024 canvas
        .frame(width: 1024, height: 1024)
    }

    /// A print: white border, coloured picture set high, like an instant photo.
    func photo(_ inner: Color) -> some View {
        let u = Self.u
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1.5 * u).fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            Rectangle().fill(inner).frame(width: 27 * u, height: 27 * u).padding(.top, 2 * u)
        }
        .frame(width: 31 * u, height: 38 * u)
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
