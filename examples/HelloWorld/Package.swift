// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelloWorld",
    // Required because this app links SwiflowWeb, which transitively pulls
    // Hummingbird 2.x (macOS 14+). Without this floor, `swift build` fails
    // with "executable 'App' requires macos 10.13, but depends on the
    // product 'SwiflowWeb' which requires macos 14.0".
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
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
