// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlanceCore",
    // macOS 14:選單列 app 用到 openSettings 等 14.0 API。
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
        .executable(name: "glance-cli", targets: ["glance-cli"]),
        // 選單列 app:以 SPM executable 編譯,再由 formula/腳本組成 .app bundle。
        // 如此 Homebrew 從源碼安裝可純用 swift build,免去 xcodebuild 解析套件時的 nested sandbox。
        .executable(name: "Glance", targets: ["GlanceApp"]),
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
        .executableTarget(
            name: "GlanceApp",
            dependencies: ["GlanceCore"],
            path: "GlanceApp",
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
