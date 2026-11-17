// swift-tools-version: 6.0
// 6.0 is the newest tools version the GitHub `macos-26` runner's Xcode accepts with room to
// spare; see .github/workflows/ci.yml before raising it.

import PackageDescription

let package = Package(
    name: "Turnover",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TurnoverKit", targets: ["TurnoverKit"]),
        .library(name: "RingModel", targets: ["RingModel"]),
        .library(name: "TurnoverAppCore", targets: ["TurnoverAppCore"]),
        .executable(name: "turnover", targets: ["TurnoverCLI"]),
    ],
    targets: [
        // The core: inspection, offers and estimates, conversion actions, output placement and
        // the batch runner. Test seam #1. The Finder extension, the app and the CLI all use it.
        .target(name: "TurnoverKit"),

        // The app's own policy, kept out of the sandboxed Finder extension: how a launch opens
        // the window, the settings and Open at login, and the feedback on batches (the menu bar
        // item's rules and the notifications). Tested with seam #1's suites.
        .target(name: "TurnoverAppCore", dependencies: ["TurnoverKit"]),

        // The drag + ⇧ ring's behaviour as a state machine: events in, what to show and convert
        // out. No AppKit, so it is tested on its own. Test seam #2.
        .target(name: "RingModel", dependencies: ["TurnoverKit"]),

        // The `turnover` command, a thin wrapper over TurnoverKit.
        .executableTarget(name: "TurnoverCLI", dependencies: ["TurnoverKit"]),

        // Committed fixtures and helpers shared by every test target. Not shipped.
        .target(
            name: "TurnoverTestSupport",
            dependencies: ["TurnoverKit", "TurnoverAppCore"],
            path: "Tests/TurnoverTestSupport",
            resources: [.copy("Fixtures")]),

        .testTarget(name: "TurnoverKitTests", dependencies: ["TurnoverKit", "TurnoverTestSupport"]),
        .testTarget(name: "TurnoverAppCoreTests", dependencies: ["TurnoverAppCore", "TurnoverKit", "TurnoverTestSupport"]),
        .testTarget(name: "RingModelTests", dependencies: ["RingModel"]),
        // Depends on the executable so `swift test` builds `turnover` before running it.
        .testTarget(name: "TurnoverCLITests", dependencies: ["TurnoverCLI", "TurnoverTestSupport"]),
    ]
)
