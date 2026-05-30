// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeCases",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
