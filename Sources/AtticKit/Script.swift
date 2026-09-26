import AppKit
import Foundation
import AtticCore

/// Scripted actions for test runs of the real window: ATTIC_SCRIPT="confirm-all,section:marked,delete".
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
            }
            FileHandle.standardError.write(Data("script: \(step) -> phase \(model.phase) section \(model.section.rawValue) photos \(model.photos.count) marked \(model.marked.count) message \(model.message ?? "-")\n".utf8))
        }
    }
}
