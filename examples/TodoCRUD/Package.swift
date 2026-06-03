// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoCRUD",
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
                .product(name: "SwiflowQuery", package: "Swiflow"),
                // The fetch + JSON-decode story now lives in the SwiflowHTTP
                // module (graduated from this example's old Net.swift); it pulls
                // in JavaScriptKit/JavaScriptEventLoop transitively.
                .product(name: "SwiflowHTTP", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
