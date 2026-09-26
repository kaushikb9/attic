// Real-window check: run Attic on a fixture with scripted actions, capture
// its window, and fail if it drew blank or its text is not what's expected.
// Needs Screen Recording permission for the terminal; without it, says so and
// exits 0 (skipped, not passed).
//   swift scripts/window-check.swift <Attic.app> <fixture dir> <script> [--expect <text>]... [--reject <text>]... [--save <png>]
// --expect/--reject match the window's text as Vision reads it, on-device.
// The app is launched in the background: a launch that takes the keyboard
// turns whatever the person at the Mac is typing into Attic shortcuts
// ("s" skips, "a" keeps all). That was the "stale first section" of 2026-09-26.
import AppKit
import CoreGraphics
import Foundation
import Vision

var args = Array(CommandLine.arguments.dropFirst())
var expect: [String] = [], reject: [String] = [], save: String?
while let i = args.firstIndex(where: { $0.hasPrefix("--") }), args.count > i + 1 {
    let (flag, value) = (args[i], args[i + 1])
    switch flag {
    case "--expect": expect.append(value)
    case "--reject": reject.append(value)
    case "--save": save = value
    default: print("window-check: unknown option \(flag)"); exit(2)
    }
    args.removeSubrange(i...(i + 1))
}
guard args.count == 3 else {
    print("usage: window-check.swift <Attic.app> <fixture dir> <script> [--expect text] [--reject text] [--save png]"); exit(2)
}
let (app, fixture, script) = (URL(fileURLWithPath: args[0]), args[1], args[2])
let label = script.isEmpty ? "launch" : script
let home = FileManager.default.temporaryDirectory.appendingPathComponent("attic-window-\(UUID().uuidString)")

let config = NSWorkspace.OpenConfiguration()
config.activates = false
config.createsNewApplicationInstance = true
config.addsToRecentItems = false
config.environment = ["ATTIC_FIXTURE": fixture, "ATTIC_HOME": home.path, "ATTIC_SCRIPT": script]
var launched: NSRunningApplication?
var launchError: Error?
let opened = DispatchSemaphore(value: 0)
NSWorkspace.shared.openApplication(at: app, configuration: config) { r, e in launched = r; launchError = e; opened.signal() }
opened.wait()
guard let p = launched else { print("window-check: could not open \(app.path): \(launchError.map { "\($0)" } ?? "no app")"); exit(1) }
// exit() skips defer, so every way out goes through done().
func done(_ code: Int32) -> Never { p.forceTerminate(); exit(code) }
Thread.sleep(forTimeInterval: 2.5 + Double(script.split(separator: ",").count) * 0.8)

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard let w = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == p.processIdentifier
        && (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 100 }),
      let id = w[kCGWindowNumber as String] as? CGWindowID else {
    print("window-check: no Attic window appeared for \"\(label)\""); done(1)
}
let out = save.map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent("w.png")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let cap = Process()
cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
// Checks capture without the shadow (the colour threshold was measured that
// way); saved screenshots keep it.
cap.arguments = (save == nil ? ["-x", "-o"] : ["-x"]) + ["-l", "\(id)", out.path]
try cap.run(); cap.waitUntilExit()
guard let img = NSImage(contentsOf: out), let rep = img.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: img.tiffRepresentation ?? Data()),
      let cg = rep.cgImage else {
    print("window-check: skipped (screen capture not allowed for this terminal)"); done(0)
}
// A drawn window has text: many distinct colours. A blank one has a handful.
var colours = Set<UInt32>()
for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
    for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        colours.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
    }
}
if colours.count < 300 {  // blank measured 101 (window shading), drawn 1100+
    print("window-check: FAILED, window drew blank after \"\(label)\" (\(colours.count) colours). Capture: \(out.path)"); done(1)
}
if !expect.isEmpty || !reject.isEmpty {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: cg).perform([req])
    let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    let missing = expect.filter { !text.localizedCaseInsensitiveContains($0) }
    let found = reject.filter { text.localizedCaseInsensitiveContains($0) }
    if !missing.isEmpty || !found.isEmpty {
        print("window-check: FAILED after \"\(label)\": " + (missing.map { "no \"\($0)\"" } + found.map { "shows \"\($0)\"" }).joined(separator: ", ")
              + ". Window read: \(text.prefix(300)). Capture: \(out.path)")
        done(1)
    }
}
print("window-check: \"\(label)\" drew \(colours.count) colours" + (expect.isEmpty && reject.isEmpty ? "" : ", text as expected"))
done(0)
