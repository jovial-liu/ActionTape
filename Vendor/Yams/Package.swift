// swift-tools-version:5.7
// ActionTape's build-only manifest for the vendored Yams 6.2.2 sources.
// Upstream test fixtures and development tooling are intentionally not vendored.
// See NOTICE.md and LICENSE; no third-party implementation files are modified.
import PackageDescription

let package = Package(
    name: "Yams",
    products: [
        .library(name: "Yams", targets: ["Yams"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CYaml",
            exclude: ["CMakeLists.txt"],
            cSettings: [.define("YAML_DECLARE_STATIC")]
        ),
        .target(
            name: "Yams",
            dependencies: ["CYaml"],
            exclude: ["CMakeLists.txt"],
            cSettings: [.define("YAML_DECLARE_STATIC")]
        )
    ]
)
