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
        .target(
            name: "GlanceCore",
            linkerSettings: [
                // IOReport 私有功耗符號位於 libIOReport.dylib(dyld shared cache),
                // 需顯式連結才能解析 @_silgen_name 綁定的 IOReport* 符號。
                .linkedLibrary("IOReport"),
            ]
        ),
        .executableTarget(name: "glance-cli", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
