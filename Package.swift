// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlanceCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
        .executable(name: "glance-cli", targets: ["glance-cli"]),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "glance-cli", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
