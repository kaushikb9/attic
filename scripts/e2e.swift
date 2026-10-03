// End-to-end walks: Attic opens in the background on the demo library and is
// used through the accessibility API, the way VoiceOver uses it: buttons
// pressed, sidebar rows selected, menu items chosen, text read back. It never
// moves the mouse or takes the keyboard; keyboard shortcuts go through the
// app's own event queue (ATTIC_SCRIPT type:). Each walk starts fresh.
//   swift scripts/e2e.swift <Attic.app> [walk name...]
// Needs Accessibility permission for the terminal; without it, says so and
// exits 0 (skipped, not passed). "Name places with Apple Maps" is never
// pressed: it would send the demo's locations to Apple.
import AppKit
import ApplicationServices

guard AXIsProcessTrusted() else { print("e2e: skipped (no Accessibility permission for this terminal)"); exit(0) }
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: e2e.swift <Attic.app> [walk...]"); exit(2) }
let appURL = URL(fileURLWithPath: args[1])
let only = Set(args.dropFirst(2))
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("attic-e2e-\(UUID().uuidString)")
let template = root.appendingPathComponent("demo")
let make = Process()
make.executableURL = appURL.appendingPathComponent("Contents/MacOS/Attic")
make.arguments = ["--make-demo", template.path]
make.standardOutput = FileHandle.nullDevice
try make.run(); make.waitUntilExit()

struct Failure: Error, CustomStringConvertible { let description: String }

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
/// What a person would read on an element: its value, title, description or help.
func words(_ e: AXUIElement) -> [String] {
    [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
        .compactMap { attr(e, $0) as? String }.filter { !$0.isEmpty }
}

/// One fresh launch: its own state folder, export folder and copy of the demo library.
final class Walk {
    let app: NSRunningApplication
    let ax: AXUIElement
    let home: URL, library: URL, best: URL

    init(script: String = "") throws {
        home = root.appendingPathComponent(UUID().uuidString)
        library = home.appendingPathComponent("library")
        best = home.appendingPathComponent("best-of")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.copyItem(at: template, to: library)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.createsNewApplicationInstance = true
        config.addsToRecentItems = false
        config.environment = ["ATTIC_FIXTURE": library.path, "ATTIC_HOME": home.path, "ATTIC_BEST": best.path, "ATTIC_SCRIPT": script]
        var launched: NSRunningApplication?, failure: Error?
        let opened = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { r, e in launched = r; failure = e; opened.signal() }
        opened.wait()
        guard let app = launched else { throw Failure(description: "could not open Attic: \(failure.map { "\($0)" } ?? "no app")") }
        self.app = app
        ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 3)
        try expect("Duplicates", within: 15)  // the scan finished and the first section drew
    }

    func close() { app.forceTerminate() }

    var window: AXUIElement? { (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first }

    func all(_ e: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
        depth > 40 ? [] : [e] + children(e).flatMap { all($0, depth + 1) }
    }

    func texts() -> [String] { window.map { all($0).flatMap(words) } ?? [] }

    /// Polls until `test` holds, like a person waiting for the screen to settle.
    func until(_ what: String, within s: Double = 4, _ test: () -> Bool) throws {
        let end = Date().addingTimeInterval(s)
        while Date() < end { if test() { return }; Thread.sleep(forTimeInterval: 0.1) }
        throw Failure(description: what + ". The window reads: " + texts().joined(separator: " | ").prefix(400))
    }

    func expect(_ s: String, within t: Double = 4) throws {
        try until("no \"\(s)\"", within: t) { texts().contains { $0.contains(s) } }
    }

    func reject(_ s: String) throws {
        try until("still shows \"\(s)\"") { !texts().contains { $0.contains(s) } }
    }

    func element(_ label: String) throws -> AXUIElement {
        var found: AXUIElement?
        try until("nothing to press called \"\(label)\"") {
            found = window.flatMap { w in all(w).first { words($0).contains(label) && hasPress($0) } }
            return found != nil
        }
        return found!
    }

    func hasPress(_ e: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        return (names as? [String] ?? []).contains(kAXPressAction)
    }

    func press(_ label: String) throws {
        let e = try element(label)
        guard AXUIElementPerformAction(e, kAXPressAction as CFString) == .success else { throw Failure(description: "pressing \"\(label)\" failed") }
    }

    /// Selects a sidebar row by its name, as a click would.
    func sidebar(_ name: String) throws {
        var row: AXUIElement?
        try until("no sidebar row \"\(name)\"") {
            row = window.flatMap { w in all(w).first { attr($0, kAXRoleAttribute) as? String == kAXRowRole && all($0).contains { words($0).contains(name) } } }
            return row != nil
        }
        AXUIElementSetAttributeValue(row!, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    }

    /// The number shown beside a sidebar row, or nil when it shows none.
    func count(_ name: String) -> Int? {
        guard let w = window, let row = all(w).first(where: { attr($0, kAXRoleAttribute) as? String == kAXRowRole && all($0).contains { words($0).contains(name) } })
        else { return nil }
        return all(row).flatMap(words).compactMap(Int.init).first
    }

    func expectCount(_ name: String, _ n: Int?) throws {
        try until("sidebar \(name) shows \(count(name).map(String.init) ?? "no count"), expected \(n.map(String.init) ?? "no count")") { count(name) == n }
    }

    /// Chooses a menu item, e.g. menu("Edit", "Undo").
    func menu(_ top: String, _ item: String) throws {
        guard let bar = attr(ax, kAXMenuBarAttribute).map({ $0 as! AXUIElement }),
              let title = children(bar).first(where: { words($0).contains(top) }),
              let entry = all(title).first(where: { attr($0, kAXRoleAttribute) as? String == kAXMenuItemRole && words($0).contains(item) })
        else { throw Failure(description: "no menu item \(top) ▸ \(item)") }
        guard AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success else { throw Failure(description: "\(top) ▸ \(item) failed") }
    }

    /// Types into the focused text field and submits it.
    func enter(_ text: String) throws {
        var field: AXUIElement?
        try until("no text field") {
            field = window.flatMap { w in all(w).first { attr($0, kAXRoleAttribute) as? String == kAXTextFieldRole } }
            return field != nil
        }
        AXUIElementSetAttributeValue(field!, kAXValueAttribute as CFString, text as CFString)
        AXUIElementPerformAction(field!, kAXConfirmAction as CFString)
    }
}

func check(_ ok: Bool, _ what: String) throws { if !ok { throw Failure(description: what) } }

// The walks. The demo library has 1 duplicate group (a sunset re-saved
// small), 2 retake groups (a 3-shot lunch, then a 5-shot beach photo) and
// 3 events to do.
let walks: [(String, (Walk) throws -> Void)] = [
    ("first-launch", { w in
        try w.expect("1 group · 1 suggested to delete")
        try w.expectCount("Duplicates", 1); try w.expectCount("Retakes", 2); try w.expectCount("Best of", 3)
        try w.expectCount("Marked for deletion", nil)
        try w.expect("Keep #1, the full-size original. The others are smaller copies.")
    }),
    ("duplicates-by-clicks", { w in
        try w.press("Deleting shot 2. Switch to keep")   // keep both: the main button says so
        try w.expect("Keeping shot 2. Switch to delete")
        try w.press("Keeping shot 2. Switch to delete")
        try w.press("Mark 1 for deletion")
        try w.expect("Marked 1 for deletion · ⌘Z undoes")
        try w.expect("0 groups"); try w.expectCount("Marked for deletion", 1)
        try w.menu("Edit", "Undo")
        try w.expect("1 group · 1 suggested to delete"); try w.expectCount("Marked for deletion", nil)
        try w.press("Keep all")
        try w.expect("Kept all 2 · ⌘Z undoes")
        try w.menu("Edit", "Undo")
        try w.press("Skip")
        try w.expect("Skipped until next launch · ⌘Z undoes"); try w.expectCount("Duplicates", nil)
        try w.menu("Edit", "Undo")
        try w.expect("1 group"); try w.expectCount("Duplicates", 1)
        try w.press("Keep all"); try w.press("Dismiss")
        try w.reject("Kept all 2")
    }),
    ("keyboard", { w in
        // j moves to the beach group, a keeps all of it, space toggles the
        // lunch's first shot back to keep, return confirms the lunch.
        // The keys fire on their own schedule, so only the end state is checked.
        try w.expect("Marked 1 for deletion · ⌘Z undoes", within: 8)
        try w.expectCount("Retakes", nil); try w.expectCount("Marked for deletion", 1)
        try w.reject("5 shots")
    }),
    ("retakes-marked-delete", { w in
        try w.sidebar("Retakes")
        try w.expect("2 groups · 6 suggested to delete")
        try w.press("Not retakes")
        try w.expect("Kept all 3, not retakes · ⌘Z undoes")
        try w.menu("Edit", "Undo")
        try w.press("Mark 2 for deletion")
        try w.expect("Marked 2 for deletion"); try w.expectCount("Marked for deletion", 2)
        try w.sidebar("Marked for deletion")
        try w.expect("Delete 2 from Photos…")
        try w.press("Keep instead")
        try w.expect("Kept 1 · ⌘Z undoes"); try w.expect("Delete 1 from Photos…")
        try w.press("Delete 1 from Photos…")
        try w.expect("Deleted 1 photo. They stay in Recently Deleted in Photos for 30 days.")
        try w.expect("Nothing marked.")
        let gone = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: w.library.appendingPathComponent("deleted.json")))) ?? []
        try check(gone.count == 1, "the library recorded \(gone.count) deletions, expected 1")
    }),
    ("best-of-export-rename-skip", { w in
        try w.sidebar("Best of")
        try w.expect("3 events to do · 0 exported · 0 photos in")
        try w.press("Photo 1, picked")
        try w.expect("Export 2 to best-of")
        try w.press("Export 2 to best-of")
        try w.expect("1 exported · 2 photos in")
        try w.sidebar("Retakes"); try w.sidebar("Best of")   // the exported event leaves To do
        try w.expect("2 events to do")
        let folders = try fm.contentsOfDirectory(atPath: w.best.path).filter { !$0.hasPrefix(".") && $0 != "manifest.json" }
        let jpgs = try folders.flatMap { try fm.contentsOfDirectory(atPath: w.best.appendingPathComponent($0).path) }.filter { $0.hasSuffix(".jpg") }
        try check(folders.count == 1 && jpgs.count == 2, "export wrote \(folders.count) folders and \(jpgs.count) photos, expected 1 and 2")
        try check(fm.fileExists(atPath: w.best.appendingPathComponent("manifest.json").path), "no manifest.json")
        try w.press("Rename")
        try w.enter("E2E weekend")
        try w.expect("E2E weekend")
        try w.press("Skip event")
        try w.expect("1 event to do")
        try w.press("Skipped")
        try w.press("Reopen")
        try w.press("To do")
        try w.expect("2 events to do")
    }),
    ("menus-and-rescan", { w in
        try w.menu("Go", "Retakes"); try w.expect("2 groups · 6 suggested to delete")
        try w.menu("Go", "Best of"); try w.expect("events to do")
        try w.menu("Go", "Marked for deletion"); try w.expect("Nothing marked.")
        try w.menu("Go", "Duplicates")
        try w.press("Keep all")
        try w.menu("File", "Rescan Library")
        try w.expect("0 groups"); try w.expectCount("Retakes", 2)   // decisions survive a rescan
    }),
]

let scripts = ["keyboard": "section:retakes,type:j,type:a,type: ,type:\r"]
var failed = 0
for (name, body) in walks where only.isEmpty || only.contains(name) {
    let started = Date()
    do {
        let w = try Walk(script: scripts[name] ?? "")
        defer { w.close() }
        try body(w)
        print("e2e: ✓ \(name) (\(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
    } catch {
        failed += 1
        print("e2e: ✘ \(name): \(error)")
    }
}
try? fm.removeItem(at: root)
print(failed == 0 ? "e2e: all walks passed" : "e2e: \(failed) walk\(failed == 1 ? "" : "s") failed")
exit(failed == 0 ? 0 : 1)
