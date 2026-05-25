// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Swiflow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Swiflow", targets: ["Swiflow"]),
        .library(name: "SwiflowWeb", targets: ["SwiflowWeb"]),
        .library(name: "SwiflowRouter", targets: ["SwiflowRouter"]),
        .library(name: "SwiflowTesting", targets: ["SwiflowTesting"]),
        .executable(name: "swiflow", targets: ["SwiflowCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.6.0")),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", .upToNextMinor(from: "2.2.0")),
        // swift-syntax powers the @Component macro compiler plugin.
        // Pinned to upToNextMinor: 600.x covers Swift 6; 601+ may introduce breaking API changes.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMinor(from: "600.0.0")),
    ],
    targets: [
        // Compiler plugin — runs on the macOS HOST at build time; never in the WASM binary.
        .macro(
            name: "SwiflowMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/SwiflowMacrosPlugin",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Swiflow",
            dependencies: ["SwiflowMacrosPlugin"],
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
        .target(
            name: "SwiflowRouter",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowRouter",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowTesting",
            dependencies: ["Swiflow"],
            path: "Sources/SwiflowTesting",
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
        .testTarget(
            name: "SwiflowRouterTests",
            dependencies: ["SwiflowRouter", "SwiflowTesting"],
            path: "Tests/SwiflowRouterTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowTestingTests",
            dependencies: ["SwiflowTesting", "Swiflow"],
            path: "Tests/SwiflowTestingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowMacrosTests",
            dependencies: [
                "SwiflowMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/SwiflowMacrosTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
