// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MissionControl",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        .package(path: "../.."),
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowDOM", package: "Swiflow"),
                .product(name: "SwiflowUI", package: "Swiflow"),
                .product(name: "SwiflowRouter", package: "Swiflow"),
                .product(name: "SwiflowQuery", package: "Swiflow"),
                .product(name: "SwiflowFetcher", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
