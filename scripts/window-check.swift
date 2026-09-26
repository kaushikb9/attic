// Real-window check: run Attic on the fixture with scripted actions, capture
// its window, and fail if it drew blank. Needs Screen Recording permission for
// the terminal; without it, says so and exits 0 (skipped, not passed).
//   swift scripts/window-check.swift <Attic binary> <fixture dir> <script>
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let (bin, fixture, script) = (args[1], args[2], args[3])
let home = FileManager.default.temporaryDirectory.appendingPathComponent("attic-window-\(UUID().uuidString)")
let p = Process()
p.executableURL = URL(fileURLWithPath: bin)
p.environment = ["ATTIC_FIXTURE": fixture, "ATTIC_HOME": home.path, "ATTIC_BEST": home.appendingPathComponent("best").path,
                 "ATTIC_SCRIPT": script, "HOME": NSHomeDirectory()]
p.standardOutput = FileHandle.nullDevice
p.standardError = FileHandle.nullDevice
try p.run()
// exit() skips defer, so every way out goes through done().
func done(_ code: Int32) -> Never { p.terminate(); p.waitUntilExit(); exit(code) }
Thread.sleep(forTimeInterval: 2.5 + Double(script.split(separator: ",").count) * 0.8)

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard let w = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == p.processIdentifier
        && (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 100 }),
      let id = w[kCGWindowNumber as String] as? CGWindowID else {
    print("window-check: no Attic window appeared for \"\(script)\""); done(1)
}
let out = home.appendingPathComponent("w.png")
let cap = Process()
cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
cap.arguments = ["-x", "-o", "-l", "\(id)", out.path]
try cap.run(); cap.waitUntilExit()
guard let img = NSImage(contentsOf: out), let rep = img.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: img.tiffRepresentation ?? Data()) else {
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
    print("window-check: FAILED, window drew blank after \"\(script)\" (\(colours.count) colours). Capture: \(out.path)"); done(1)
}
print("window-check: \"\(script)\" drew \(colours.count) colours")
done(0)
