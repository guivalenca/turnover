// swift-tools-version: 6.0
// 6.0 is the newest tools version the GitHub `macos-26` runner's Xcode accepts with room to
// spare; see .github/workflows/ci.yml before raising it.

import PackageDescription

let package = Package(
    name: "Turnover",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TurnoverKit", targets: ["TurnoverKit"]),
        .executable(name: "turnover", targets: ["TurnoverCLI"]),
    ],
    targets: [
        // The core: inspection, actions, conversion and output placement. Test seam #1.
        .target(name: "TurnoverKit"),

        // The `turnover` command, a thin wrapper over TurnoverKit.
        .executableTarget(name: "TurnoverCLI", dependencies: ["TurnoverKit"]),

        // Committed fixtures and helpers shared by every test target. Not shipped.
        .target(
            name: "TurnoverTestSupport",
            dependencies: ["TurnoverKit"],
            path: "Tests/TurnoverTestSupport",
            resources: [.copy("Fixtures")]),

        .testTarget(name: "TurnoverKitTests", dependencies: ["TurnoverKit", "TurnoverTestSupport"]),
        // Depends on the executable so `swift test` builds `turnover` before running it.
        .testTarget(name: "TurnoverCLITests", dependencies: ["TurnoverCLI", "TurnoverTestSupport"]),
    ]
)
