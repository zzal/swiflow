// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QueryDemo",
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    // SwiflowDOM itself only links Swiflow + JavaScriptKit and doesn't
    // need macOS 14; SwiftPM just propagates the package-level platform
    // floor to every consumer, regardless of which product they import.
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
                .product(name: "SwiflowQuery", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
