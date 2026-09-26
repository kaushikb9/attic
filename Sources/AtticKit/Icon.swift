import AppKit
import SwiftUI

/// The app icon, drawn in code so there is no binary asset to keep in sync.
/// Golden attic light and two photos, nothing else. The light fills the
/// whole rounded square: macOS 26 puts icons that don't fill it into a grey
/// tile. Tuned for the Dock: one bold field, big prints, no thin lines.
/// Geometry is on a 100-unit grid, scaled to the 1000 px icon body.
struct IconArt: View {
    static let u: CGFloat = 12.2  // px per grid unit: the 82-unit body is 1000 px
    let light = RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.84), Color(red: 1, green: 0.78, blue: 0.38),
                                        Color(red: 0.93, green: 0.55, blue: 0.13)],
                               center: UnitPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: 720)
    let red = Color(red: 0.91, green: 0.31, blue: 0.23)
    let blue = Color(red: 0.18, green: 0.49, blue: 0.88)

    var body: some View {
        let u = Self.u
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous).fill(light).frame(width: 1000, height: 1000)
            photo(red).rotationEffect(.degrees(-12)).offset(x: -11.5 * u, y: 3 * u)
            photo(blue).rotationEffect(.degrees(10)).offset(x: 11.5 * u, y: -3 * u)
        }
        .clipShape(RoundedRectangle(cornerRadius: 225, style: .continuous))
        .frame(width: 1000, height: 1000)
        .scaleEffect(0.824)  // macOS icon grid: 824 pt body inside the 1024 canvas
        .frame(width: 1024, height: 1024)
    }

    /// A print: white border, coloured picture set high, like an instant photo.
    func photo(_ inner: Color) -> some View {
        let u = Self.u
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1.5 * u).fill(Color.white)
                .shadow(color: Color(red: 0.45, green: 0.22, blue: 0).opacity(0.35), radius: 16, y: 10)
            Rectangle().fill(inner).frame(width: 28 * u, height: 28 * u).padding(.top, 2.1 * u)
        }
        .frame(width: 32 * u, height: 40 * u)
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
