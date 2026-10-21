// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CockpitCore",
    defaultLocalization: "fr",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CockpitCore", targets: ["CockpitCore"])],
    targets: [
        .target(name: "CockpitCore"),
        .testTarget(name: "CockpitCoreTests", dependencies: ["CockpitCore"]),
    ]
)
