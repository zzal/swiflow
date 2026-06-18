// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RegionDemo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "App", targets: ["App"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
