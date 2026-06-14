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
        .library(name: "SwiflowDOM", targets: ["SwiflowDOM"]),
        .library(name: "SwiflowRouter", targets: ["SwiflowRouter"]),
        .library(name: "SwiflowTesting", targets: ["SwiflowTesting"]),
        .library(name: "SwiflowQuery", targets: ["SwiflowQuery"]),
        .library(name: "SwiflowFetcher", targets: ["SwiflowFetcher"]),
        .library(name: "SwiflowStore", targets: ["SwiflowStore"]),
        .library(name: "SwiflowUI", targets: ["SwiflowUI"]),
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
        // swift-crypto's `Crypto` module exposes SHA256 (and friends) with the
        // same API as Apple's CryptoKit but builds on Linux too. We use it in
        // `SwiflowCLI/BundleManifest.swift` to hash artifact bytes; CryptoKit
        // on its own would break CI's Linux build. swift-crypto is already a
        // transitive dependency via hummingbird / swift-certificates, so this
        // declaration just makes the dependency edge explicit (no new graph).
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
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
            name: "SwiflowDOM",
            dependencies: [
                "Swiflow",
                "SwiflowQuery",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowDOM",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SwiflowCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                // Crypto: cross-platform SHA256 for `BundleManifest`. On Apple
                // we'd just use CryptoKit; swift-crypto's `Crypto` module has
                // an API-compatible SHA256 that also builds on Linux.
                .product(name: "Crypto", package: "swift-crypto"),
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
            dependencies: ["Swiflow", "SwiflowQuery"],
            path: "Sources/SwiflowTesting",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowQuery",
            dependencies: [
                "Swiflow",
                "SwiflowMacrosPlugin",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowQuery"
        ),
        // Standalone JSON-over-`fetch` client (graduated from the TodoCRUD
        // example's Net.swift). WASM-only at runtime — the `HTTP` client is
        // behind `#if canImport(JavaScriptKit)`; `JSONValue`/`HTTPError`
        // compile everywhere (and are host-tested).
        .target(
            name: "SwiflowFetcher",
            dependencies: [
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowFetcher",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Browser-persistence primitive: an async key/value store over
        // IndexedDB. The `PersistentStore` is WASM-only (behind
        // `#if canImport(JavaScriptKit)`); the `JSONValueEncoder` — the encode
        // counterpart to JavaScriptKit's `JSValueDecoder`, which JavaScriptKit
        // doesn't ship — is pure Swift and host-tested. Reuses SwiflowFetcher's
        // `JSONValue`/`.jsonString` for the wire format.
        .target(
            name: "SwiflowStore",
            dependencies: [
                "SwiflowFetcher",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowStore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SwiflowUI",
            dependencies: [
                "Swiflow",
            ],
            path: "Sources/SwiflowUI",
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
            // Fixtures/ holds test data read source-relative via #filePath
            // (e.g. CompilerBypassTests' swift build -v sample), not bundled
            // resources — exclude it so SwiftPM doesn't flag it as unhandled.
            exclude: ["Fixtures"],
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
            name: "SwiflowQueryTests",
            dependencies: ["SwiflowQuery", "SwiflowTesting", "Swiflow"],
            path: "Tests/SwiflowQueryTests"
        ),
        .testTarget(
            name: "SwiflowFetcherTests",
            dependencies: ["SwiflowFetcher"],
            path: "Tests/SwiflowFetcherTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowStoreTests",
            dependencies: ["SwiflowStore"],
            path: "Tests/SwiflowStoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiflowUITests",
            dependencies: ["SwiflowUI", "Swiflow"],
            path: "Tests/SwiflowUITests",
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
