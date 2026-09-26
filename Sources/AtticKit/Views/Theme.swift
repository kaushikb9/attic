import AppKit
import SwiftUI

/// Six design tokens (paper, ink, muted, line, card, gold), plus a
/// delete red that only ever means "this leaves your library".
public enum Theme {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    public static let bg = dynamic(0xFAF8F4, 0x131210)
    public static let card = dynamic(0xFFFFFF, 0x1B1A17)
    public static let ink = dynamic(0x1C1B18, 0xE8E4DC)
    public static let muted = dynamic(0x78736A, 0x8F887C)
    public static let line = dynamic(0xE6E1D7, 0x2A2721)
    public static let gold = dynamic(0xA8720A, 0xD49A2A)
    public static let goldSoft = dynamic(0xF4EAD2, 0x2C2415)
    public static let del = dynamic(0xB4432F, 0xE07A64)
    public static let delSoft = dynamic(0xF6E3DE, 0x2E1B16)

    // Four sizes, no fifth (tokens.css), plus 20 for the page title.
    public static let body = Font.system(size: 17)
    public static let item = Font.system(size: 15.5, weight: .semibold)
    public static let second = Font.system(size: 15)
    public static let caption = Font.system(size: 13)
    public static let title = Font.system(size: 20, weight: .semibold)
}

struct ActionButton: ButtonStyle {
    enum Kind { case primary, danger, plain }
    var kind: Kind = .plain
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .foregroundStyle(kind == .plain ? Theme.ink : Theme.card)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                kind == .primary ? Theme.ink : kind == .danger ? Theme.del : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(kind == .plain ? Theme.line : .clear))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// "1 group", "3 groups".
func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) \(n == 1 ? one : many ?? one + "s")" }
