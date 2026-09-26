import AppKit
import Foundation
import AtticCore
import SwiftUI

/// Renders each section to PNG from a fixture library, so the look can be
/// checked (by a person or an agent) without Photos access or real photos.
public enum Snapshot {
    public static func run(out: URL, fixture: URL) {
        var done = false
        Task { @MainActor in
            do { try await render(out: out, fixture: fixture) } catch { print("snapshot: \(error)") }
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    @MainActor
    public static func render(out: URL, fixture: URL) async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("attic-snapshot-\(UUID().uuidString)")
        let source = FolderSource(dir: fixture)
        let model = AppModel(source: source, store: StateStore(url: tmp.appendingPathComponent("state.json")),
                             analyzer: Analyzer(cacheURL: nil), exporter: Exporter(root: tmp.appendingPathComponent("best-of")))
        await model.start()
        let box = ThumbnailStoreBox(ThumbnailStore(source: source))
        for id in model.photos.keys { _ = await box.store.load(id, 400) }

        func save<V: View>(_ name: String, _ view: V, scheme: ColorScheme) {
            let r = ImageRenderer(content: view.environment(box)
                .frame(width: 1100).fixedSize(horizontal: false, vertical: true).background(Theme.bg)
                .environment(\.colorScheme, scheme))
            r.scale = 1
            // Theme colours resolve against the drawing appearance, not SwiftUI's colorScheme.
            var rendered: NSImage?
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { rendered = r.nsImage }
            guard let img = rendered, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("snapshot: \(name) rendered nothing"); return
            }
            try? png.write(to: out.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
            print("snapshot: \(name) \(Int(img.size.width))x\(Int(img.size.height))")
        }
        for scheme in [ColorScheme.light, .dark] {
            save("duplicates", GroupsContent(kind: .duplicates, model: model), scheme: scheme)
            save("retakes", GroupsContent(kind: .retakes, model: model), scheme: scheme)
            save("best-of", BestOfContent(model: model), scheme: scheme)
        }
        if let g = model.visibleGroups(.retakes).first { model.confirm(g) }
        save("marked", MarkedContent(model: model), scheme: .light)
    }
}

