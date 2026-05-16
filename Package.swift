// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
    ],
    dependencies: [
        // Pinned to minor range. JavaScriptKit's 0.x cadence has shipped
        // breaking changes across minor bumps (e.g. JSValue.function was
        // deprecated 0.21 → 0.53). Bumping the minor requires intentional
        // review of the renderer + dispatcher bridge.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .target(
            name: "Swiflow",
            path: "Sources/Swiflow",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
