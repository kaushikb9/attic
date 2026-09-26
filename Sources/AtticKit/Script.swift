import AppKit
import Foundation
import AtticCore

/// Scripted actions for test runs of the real window: ATTIC_SCRIPT="confirm-all,section:marked,delete".
/// `type:<keys>` presses keys in the window (keyboard shortcuts through the real event path).
/// Only honoured with ATTIC_FIXTURE, so it can never act on the real library.
@MainActor
enum Script {
    static func run(_ model: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard env["ATTIC_FIXTURE"] != nil, let script = env["ATTIC_SCRIPT"] else { return }
        for step in script.split(separator: ",").map(String.init) {
            try? await Task.sleep(for: .milliseconds(600))
            switch step {
            case "confirm-all":
                for g in model.visibleGroups(.duplicates) + model.visibleGroups(.retakes) { model.confirm(g) }
            case "delete": await model.deleteMarked()
            case "rescan": await model.rescan()
            case "msg": model.message = "Deleted 5 photos. They stay in Recently Deleted in Photos for 30 days."
            case "drop": model.debugDrop(Array(model.photos.keys.prefix(3)))
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            case "wait": try? await Task.sleep(for: .seconds(2))
            default:
                if step.hasPrefix("size:"), let wh = Optional(step.dropFirst(5).split(separator: "x").compactMap { Double($0) }), wh.count == 2,
                   let win = NSApp.windows.first(where: { $0.isVisible }) {
                    win.setContentSize(NSSize(width: wh[0], height: wh[1])); win.center()
                }
                if step.hasPrefix("section:"), let s = AppModel.Section(rawValue: String(step.dropFirst(8))) { model.section = s }
                if step.hasPrefix("type:") { type(String(step.dropFirst(5))) }
            }
            FileHandle.standardError.write(Data("script: \(step) -> phase \(model.phase) section \(model.section.rawValue) photos \(model.photos.count) marked \(model.marked.count) message \(model.message ?? "-")\n".utf8))
        }
    }

    /// Keystrokes through the app's own event queue, as if typed into the window.
    static func type(_ chars: String) {
        guard let win = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        for c in chars.map(String.init) {
            for kind in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: win.windowNumber, context: nil, characters: c,
                                            charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
        }
    }
}
