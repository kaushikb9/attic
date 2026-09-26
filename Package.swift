// swift-tools-version: 6.0
import PackageDescription

// AtticCore: pure logic (grouping, ranking, events, state). No PhotoKit, fully unit-tested.
// AtticKit:  PhotoKit, Vision, export and the SwiftUI views.
// Attic:     the app entry point. scripts/build-app.sh wraps it into Attic.app.
// ConciseMagicFile: crash messages name "Module/File.swift", never the builder's home folder.
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5), .enableUpcomingFeature("ConciseMagicFile")]

let package = Package(
    name: "Attic",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "AtticCore", swiftSettings: v5),
        .target(name: "AtticKit", dependencies: ["AtticCore"], swiftSettings: v5),
        .executableTarget(name: "Attic", dependencies: ["AtticKit"], swiftSettings: v5),
        .testTarget(name: "AtticCoreTests", dependencies: ["AtticCore"], swiftSettings: v5),
        .testTarget(name: "AtticKitTests", dependencies: ["AtticKit", "AtticCore"], swiftSettings: v5),
    ]
)
