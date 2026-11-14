// swift-tools-version: 6.0
import PackageDescription

// Varta for macOS.
//
// `VartaCore` is the port of app/watchcore.py, app/regions.py and
// app/history.py: pure logic over a clock, no networking, no UI, so the rules
// that decide "calm" versus "not watching" are tested without a feed
// (`swift test`).
//
// The app itself is built by Varta.xcodeproj (generated from project.yml by
// XcodeGen), because time-sensitive notifications need an entitlement backed by
// a provisioning profile, and the V2 widget needs an app extension. Neither is
// something SwiftPM can build. This package is the core and its tests; the app
// and widget sources are compiled by Xcode only.
let package = Package(
    name: "Varta",
    // macOS 14: @Observable, and desktop widgets for V2. See the Mac Ports Plan.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VartaCore", targets: ["VartaCore"]),
    ],
    targets: [
        .target(
            name: "VartaCore",
            path: "Sources/VartaCore"
        ),
        .testTarget(
            name: "VartaCoreTests",
            dependencies: ["VartaCore"],
            path: "Tests/VartaCoreTests",
            // A cached feed response, so tests never touch the real feed: it
            // rate-limits by IP, and the same IP may be running a live watch.
            resources: [.copy("Fixtures")]
        ),
    ]
)
