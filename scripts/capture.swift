// Run Attic on a folder library with scripted steps and save its window as PNG.
//   swift scripts/capture.swift <Attic binary> <library dir> <steps> <out.png>
// Needs Screen Recording permission for the terminal.
import AppKit
import CoreGraphics
import Foundation

let a = CommandLine.arguments
let (bin, lib, steps, out) = (a[1], a[2], a[3], a[4])
let home = FileManager.default.temporaryDirectory.appendingPathComponent("attic-shot-\(UUID().uuidString)")
let p = Process()
p.executableURL = URL(fileURLWithPath: bin)
p.environment = ["ATTIC_FIXTURE": lib, "ATTIC_HOME": home.path, "ATTIC_SCRIPT": steps, "HOME": NSHomeDirectory()]
p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
try p.run()
func done(_ code: Int32) -> Never { p.terminate(); p.waitUntilExit(); exit(code) }
Thread.sleep(forTimeInterval: 3 + Double(steps.split(separator: ",").count) * 0.8)
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
guard let w = list.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == p.processIdentifier
        && (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 100 }),
      let id = w[kCGWindowNumber as String] as? CGWindowID else { print("capture: no window"); done(1) }
let cap = Process()
cap.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
cap.arguments = ["-x", "-l", "\(id)", out]
try cap.run(); cap.waitUntilExit()
print("capture: \(out)")
done(0)
