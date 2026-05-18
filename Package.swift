// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiflow",
    platforms: [
        // Bumped from .v13 → .v14 because Hummingbird 2.x requires macOS 14.
        // SwiflowCLI is the only macOS-bound product (the WASM-side libs run
        // in the browser via JavaScriptKit and aren't affected), so the
        // floor only matters for the dev server's host.
        .macOS(.v14),
    ],
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
        .executable(name: "swiflow", targets: ["SwiflowCLI"]),
    ],
    dependencies: [
        // Pinned to minor range. JavaScriptKit's 0.x cadence has shipped
        // breaking changes across minor bumps (e.g. JSValue.function was
        // deprecated 0.21 → 0.53). Bumping the minor requires intentional
        // review of the renderer + dispatcher bridge.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
        // ArgumentParser drives the swiflow CLI. Use a major-bump range —
        // 1.x has been API-stable since 2021.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // Hummingbird is the HTTP+WebSocket server for `swiflow dev`. v2 is
        // async/await native and Swift 6 strict-concurrency clean. We pin
        // to upToNextMinor — 2.x has had API drift across minor releases
        // (WebSocket router context refactor in 2.6, etc.).
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.6.0")),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", .upToNextMinor(from: "2.2.0")),
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
        .executableTarget(
            name: "SwiflowCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ],
            path: "Sources/SwiflowCLI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTests",
            dependencies: ["Swiflow"],
            path: "Tests/SwiflowTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowCLITests",
            dependencies: [
                "SwiflowCLI",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            ],
            path: "Tests/SwiflowCLITests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
