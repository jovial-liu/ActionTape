// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ActionTape",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ActionTapeCore", targets: ["ActionTapeCore"]),
        // Keep this distinct from `actiontape` on case-insensitive macOS volumes.
        .executable(name: "ActionTapeStudio", targets: ["ActionTapeStudio"]),
        .executable(name: "ActionTapePractice", targets: ["ActionTapePractice"]),
        .executable(name: "actiontape", targets: ["ActionTapeCLI"])
    ],
    dependencies: [
        // Vendored to keep first builds deterministic on restricted networks.
        // Upstream: https://github.com/jpsim/Yams (6.2.2, MIT).
        .package(path: "Vendor/Yams")
    ],
    targets: [
        .target(
            name: "ActionTapeCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .executableTarget(
            name: "ActionTapeStudio",
            dependencies: ["ActionTapeCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ActionTapeCLI",
            dependencies: ["ActionTapeCLIKit"]
        ),
        .target(
            name: "ActionTapeCLIKit",
            dependencies: ["ActionTapeCore"]
        ),
        .executableTarget(
            name: "ActionTapePractice",
            dependencies: []
        ),
        .testTarget(
            name: "ActionTapeCoreTests",
            dependencies: ["ActionTapeCore"]
        ),
        .testTarget(
            name: "ActionTapeCLIKitTests",
            dependencies: ["ActionTapeCLIKit"]
        )
    ]
)
